--!strict
--[[
    Socket Module
    ---------------
    This module provides an interface similar to socket.io for Roblox.
    It abstracts RemoteEvent usage to easily send data between the server and client.
    Usage:
        local Socket = require(path.to.SocketIO)
        local socket = Socket.new()  -- Optionally pass an existing RemoteEvent

        socket:On("EventName", function(player, data)
            -- On the server, the first argument is the player who fired the event.
            -- On the client, you receive just the data.
        end)

        socket:Emit("EventName", someData)
--]]

local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Socket = {}
Socket.__index = Socket
Socket.rooms = {}

export type ListenerCallback = (...any) -> ()
export type Socket = {
	remoteEvent: RemoteEvent,
	listeners: { [string]: ListenerCallback? },
	pendingRequests: { [string]: BindableEvent }?,
    debug: boolean,
	On: (self: Socket, eventName: string, callback: ListenerCallback) -> (),
	Off: (self: Socket, eventName: string) -> (),
	Once: (self: Socket, eventName: string, callback: ListenerCallback) -> (),
	Emit: (self: Socket, eventName: string, ...any) -> (),
	EmitTo: (self: Socket, player: Player, eventName: string, ...any) -> (),
	Call: (self: Socket, eventName: string, ...any) -> (),
	initialize: (self: Socket) -> (),
}

function Socket.new(remoteEvent: RemoteEvent?, debug: boolean?): Socket
	local self = setmetatable({}, Socket) :: Socket
    self.debug = debug or false
	if remoteEvent then
		self.remoteEvent = remoteEvent
	else
		local eventName = "SocketEvent"
        local existing = ReplicatedStorage:FindFirstChild(eventName)
        if existing and existing:IsA("RemoteEvent") then
            self.remoteEvent = existing
        else
            self.remoteEvent = Instance.new("RemoteEvent")
            self.remoteEvent.Name = eventName
            self.remoteEvent.Parent = ReplicatedStorage
        end
	end
	self.listeners = {}
	if RunService:IsClient() then
        self.pendingRequests = {}
    end
	self:initialize()
	return self
end

function Socket:initialize()
    if RunService:IsClient() then
        self.remoteEvent.OnClientEvent:Connect(function(eventName: string, ...: any)
            if eventName == "CallResponse" then
                local requestId, response = ...
                if self.pendingRequests and self.pendingRequests[requestId] then
                    self.pendingRequests[requestId]:Fire(response)
                end
            else
                local callbacks = self.listeners[eventName]
                if callbacks then
                    for _, callback in ipairs(callbacks) do
                        local success, err = pcall(callback, ...)
                        if not success then
                            warn("Error in client callback for event '" .. eventName .. "': " .. tostring(err))
                        end
                    end
                    if self.debug then
                        print("[Socket DEBUG] Triggered client event:", eventName)
                    end
                end
            end
        end)
    else
        self.remoteEvent.OnServerEvent:Connect(function(player: Player, command: string, ...: any)
            if command == "CallRequest" then
                local targetEvent, requestId = ...
                local callbacks = self.listeners[targetEvent]
                if callbacks then
                    for _, callback in ipairs(callbacks) do
                        local success, response = pcall(callback, player, select(3, ...))
                        if success then
                            self.remoteEvent:FireClient(player, "CallResponse", requestId, response)
                        else
                            warn("Error in server call callback for event '" .. targetEvent .. "': " .. tostring(response))
                        end
                    end
                    if self.debug then
                        print("[Socket DEBUG] Processed CallRequest for event:", targetEvent)
                    end
                else
                    warn("No call handler for event '" .. targetEvent .. "'")
                end
            else
                local callbacks = self.listeners[command]
                if callbacks then
                    for _, callback in ipairs(callbacks) do
                        local success, err = pcall(callback, player, ...)
                        if not success then
                            warn("Error in server callback for event '" .. command .. "': " .. tostring(err))
                        end
                    end
                    if self.debug then
                        print("[Socket DEBUG] Triggered server event:", command)
                    end
                end
            end
        end)
    end
end

function Socket:On(eventName: string, callback: ListenerCallback)
    if not self.listeners[eventName] then
        self.listeners[eventName] = {}
    end
    table.insert(self.listeners[eventName], callback)
    if self.debug then
        print("[Socket DEBUG] Registered listener for event:", eventName)
    end
    return callback
end

function Socket:Off(eventName: string, callback: ListenerCallback?)
    if not self.listeners[eventName] then
        return
    end
    if callback then
        for i, cb in ipairs(self.listeners[eventName]) do
            if cb == callback then
                table.remove(self.listeners[eventName], i)
                if self.debug then
                    print("[Socket DEBUG] Removed a listener for event:", eventName)
                end
                break
            end
        end
    else
        self.listeners[eventName] = nil
        if self.debug then
            print("[Socket DEBUG] Removed all listeners for event:", eventName)
        end
    end
end

function Socket:Once(eventName: string, callback: ListenerCallback)
    local function wrapper(...)
        self:Off(eventName)
        callback(...)
    end
    self.listeners[eventName] = wrapper
end

function Socket:Emit(eventName: string, ...: any)
    if RunService:IsClient() then
        self.remoteEvent:FireServer(eventName, ...)
    else
        self.remoteEvent:FireAllClients(eventName, ...)
    end
end

function Socket:EmitTo(player: Player, eventName: string, ...: any)
    if RunService:IsClient() then
        error("EmitTo is only available on the server!")
    else
        self.remoteEvent:FireClient(player, eventName, ...)
    end
end

function Socket:Call(eventName: string, timeout: number?, ...: any)
    if not RunService:IsClient() then
        error("Call is only available on the client!")
    end

    timeout = timeout or 5

    local requestId = HttpService:GenerateGUID(false)
    local signal = Instance.new("BindableEvent")
    self.pendingRequests[requestId] = signal
    self.remoteEvent:FireServer("CallRequest", eventName, requestId, ...)

    local startTime = tick()
    local fired = false
    local result

    local connection
    connection = signal.Event:Connect(function(value)
        result = value
        fired = true
    end)
    
    repeat
        task.wait(0.05)
    until fired or (tick() - startTime) >= timeout

    connection:Disconnect()
    self.pendingRequests[requestId] = nil

    if not fired then
        warn("Call timed out for event: " .. eventName)
        return nil
    end

    return result
end

function Socket:BroadcastExcept(skipPlayers: { Player } | Player, eventName: string, ...: any)
    if RunService:IsClient() then
        error("BroadcastExcept is only available on the server!")
    end

    local playersToSkip = {}
    if typeof(skipPlayers) == "table" then
        playersToSkip = skipPlayers :: { Player }
    else
        playersToSkip = { skipPlayers :: Player }
    end

    for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
        local skip = false
        for _, skipPlayer in ipairs(playersToSkip) do
            if p == skipPlayer then
                skip = true
                break
            end
        end
        if not skip then
            self.remoteEvent:FireClient(p, eventName, ...)
        end
    end
    if self.debug then
        local names = {}
        for _, player in ipairs(playersToSkip) do
            table.insert(names, player.Name)
        end
        print("[Socket DEBUG] Broadcasted event:", eventName, "to all except", table.concat(names, ", "))
    end
end

function Socket:JoinRoom(player: Player, roomName: string)
    if RunService:IsClient() then
        error("JoinRoom is only available on the server!")
    end

    if not self.rooms[roomName] then
        self.rooms[roomName] = {}
    end
    table.insert(self.rooms[roomName], player)
    if self.debug then
        print("[Socket DEBUG] Player", player.Name, "joined room:", roomName)
    end
end

function Socket:LeaveRoom(player: Player, roomName: string)
    if RunService:IsClient() then
        error("LeaveRoom is only available on the server!")
    end

    if not self.rooms[roomName] then
        return
    end
    for i, p in ipairs(self.rooms[roomName]) do
        if p == player then
            table.remove(self.rooms[roomName], i)
            if self.debug then
                print("[Socket DEBUG] Player", player.Name, "left room:", roomName)
            end
            break
        end
    end
    if #self.rooms[roomName] == 0 then
        self.rooms[roomName] = nil -- Remove empty room
    end
end

function Socket:BroadcastToRoom(roomName: string, eventName: string, ...: any)
    if RunService:IsClient() then
        error("BroadcastToRoom is only available on the server!")
    end

    local room = self.rooms[roomName]
    if not room then
        warn("Room", roomName, "does not exist!")
        return
    end
    for _, player in ipairs(room) do
        self.remoteEvent:FireClient(player, eventName, ...)
    end
    if self.debug then
        print("[Socket DEBUG] Broadcasted event:", eventName, "to room:", roomName)
    end
end

function Socket:Ping(): number
    if not RunService:IsClient() then
        error("Ping can only be called on the client!")
    end
    local startTime = tick()
    local pong = self:Call("Ping")
    if pong ~= "Pong" then
        warn("Unexpected Ping response")
    end
    local latency = tick() - startTime
    if self.debug then
        print("[Socket DEBUG] Ping latency:", latency)
    end
    return latency
end

return Socket