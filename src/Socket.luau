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

export type Errors = {
    REM_EVT_NOT_FOUND: string,
    DEFAULT_REM_EVT_NOT_FOUND: string,
    CALL_TIMEOUT: string,
    PING_RESPONSE: string,
    NOT_SERVER: string,
    NOT_CLIENT: string,
    NO_CALL_HANDLER: string,
    NO_ROOM: string,
    CALLBACK_ERROR: string,
}

local ERRORS: Errors = {
	REM_EVT_NOT_FOUND = "ERR_REM_EVT_NOT_FOUND | Remote event named '%s' was not found.",
	DEFAULT_REM_EVT_NOT_FOUND = "ERR_DEFAULT_REM_EVT_NOT_FOUND | Default RemoteEvent '%s' not found.",
	CALL_TIMEOUT = "ERR_CALL_TIMEOUT | Call timed out for event '%s' (requestId: %s).",
	PING_RESPONSE = "ERR_PING_RESPONSE | Unexpected Ping response for event 'Ping' (received: %s).",
	NOT_SERVER = "ERR_NOT_SERVER | This function is only available on the server.",
	NOT_CLIENT = "ERR_NOT_CLIENT | This function is only available on the client.",
	NO_CALL_HANDLER = "ERR_NO_CALL_HANDLER | No call handler for event '%s'.",
	NO_ROOM = "ERR_NO_ROOM | Room '%s' does not exist.",
	CALLBACK_ERROR = "ERR_CALLBACK_ERROR | Error in %s callback for event '%s': %s",
}

local Socket = {}
Socket.__index = Socket
Socket.rooms = {}

export type ListenerCallback = (...any) -> ()
export type Socket = {
	remoteEvent: RemoteEvent,
	listeners: { [string]: ListenerCallback? },
	pendingRequests: { [string]: BindableEvent }?,
	debug: boolean,
	incomingMiddleware: { ((direction: string, eventName: string, args: {any}) -> (string, {any})) },
	outgoingMiddleware: { ((direction: string, eventName: string, args: {any}) -> (string, {any})) },
	On: (self: Socket, eventName: string, callback: ListenerCallback) -> (),
	Off: (self: Socket, eventName: string) -> (),
	Once: (self: Socket, eventName: string, callback: ListenerCallback) -> (),
	Emit: (self: Socket, eventName: string, ...any) -> (),
	EmitTo: (self: Socket, player: Player, eventName: string, ...any) -> (),
	Call: (self: Socket, eventName: string, ...any) -> (),
	UseIncoming: (self: Socket, middleware: (string, string, {any}) -> (string, {any})) -> (),
	UseOutgoing: (self: Socket, middleware: (string, string, {any}) -> (string, {any})) -> (),
	initialize: (self: Socket) -> (),
}

function Socket.new(idOrRemoteEvent: any, debug: boolean?): Socket
	local self = setmetatable({}, Socket) :: Socket
	self.debug = debug or false

	self.incomingMiddleware = {}
	self.outgoingMiddleware = {}

	if idOrRemoteEvent then
		local t = typeof(idOrRemoteEvent)
		if t == "Instance" and idOrRemoteEvent:IsA("RemoteEvent") then
			self.remoteEvent = idOrRemoteEvent
		elseif t == "string" then
			local eventName = idOrRemoteEvent
			local existing = ReplicatedStorage:FindFirstChild(eventName)
			if existing and existing:IsA("RemoteEvent") then
				self.remoteEvent = existing
			else
				if RunService:IsClient() then
					error(string.format(ERRORS.REM_EVT_NOT_FOUND, eventName))
				else
					self.remoteEvent = Instance.new("RemoteEvent")
					self.remoteEvent.Name = eventName
					self.remoteEvent.Parent = ReplicatedStorage
				end
			end
		else
			local eventName = "SocketEvent"
			local existing = ReplicatedStorage:FindFirstChild(eventName)
			if existing and existing:IsA("RemoteEvent") then
				self.remoteEvent = existing
			else
				if RunService:IsClient() then
					error(string.format(ERRORS.DEFAULT_REM_EVT_NOT_FOUND, eventName))
				else
					self.remoteEvent = Instance.new("RemoteEvent")
					self.remoteEvent.Name = eventName
					self.remoteEvent.Parent = ReplicatedStorage
				end
			end
		end
	else
		local eventName = "SocketEvent"
		local existing = ReplicatedStorage:FindFirstChild(eventName)
		if existing and existing:IsA("RemoteEvent") then
			self.remoteEvent = existing
		else
			if RunService:IsClient() then
				error(string.format(ERRORS.DEFAULT_REM_EVT_NOT_FOUND, eventName))
			else
				self.remoteEvent = Instance.new("RemoteEvent")
				self.remoteEvent.Name = eventName
				self.remoteEvent.Parent = ReplicatedStorage
			end
		end
	end

	self.listeners = {}
	if RunService:IsClient() then
		self.pendingRequests = {}
	end
	self:initialize()
	return self
end

function Socket:UseIncoming(middleware: (string, string, {any}) -> (string, {any}))
	table.insert(self.incomingMiddleware, middleware)
end

function Socket:UseOutgoing(middleware: (string, string, {any}) -> (string, {any}))
	table.insert(self.outgoingMiddleware, middleware)
end

-- Add helper function to process middleware
function Socket:_applyMiddleware(middlewareList, direction: string, eventName: string, args: {any}): (string, {any})
	for _, mw in ipairs(middlewareList) do
		eventName, args = mw(direction, eventName, args)
	end
	return eventName, args
end

function Socket:initialize()
	if RunService:IsClient() then
		self.remoteEvent.OnClientEvent:Connect(function(eventName: string, ...: any)
			local args = { ... }
			eventName, args = self:_applyMiddleware(self.incomingMiddleware, "incoming", eventName, args)
			if eventName == "CallResponse" then
				local requestId, response = table.unpack(args)
				if self.pendingRequests and self.pendingRequests[requestId] then
					self.pendingRequests[requestId]:Fire(response)
				end
			else
				local callbacks = self.listeners[eventName]
				if callbacks then
					for _, callback in ipairs(callbacks) do
						local success, err = pcall(callback, table.unpack(args))
						if not success then
							warn(string.format(ERRORS.CALLBACK_ERROR, "client", eventName, tostring(err)))
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
			local args = { ... }
			command, args = self:_applyMiddleware(self.incomingMiddleware, "incoming", command, args)
			if command == "CallRequest" then
				local targetEvent, requestId = table.unpack(args)
				local callbacks = self.listeners[targetEvent]
				if callbacks then
					for _, callback in ipairs(callbacks) do
						local success, response = pcall(callback, player, select(3, table.unpack(args)))
						if success then
							self.remoteEvent:FireClient(player, "CallResponse", requestId, response)
						else
							warn(string.format(ERRORS.CALLBACK_ERROR, "server call", targetEvent, tostring(response)))
						end
					end
					if self.debug then
						print("[Socket DEBUG] Processed CallRequest for event:", targetEvent)
					end
				else
					warn(string.format(ERRORS.NO_CALL_HANDLER, targetEvent))
				end
			else
				local callbacks = self.listeners[command]
				if callbacks then
					for _, callback in ipairs(callbacks) do
						local success, err = pcall(callback, player, table.unpack(args))
						if not success then
							warn(string.format(ERRORS.CALLBACK_ERROR, "server", command, tostring(err)))
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
	local args = { ... }
	eventName, args = self:_applyMiddleware(self.outgoingMiddleware, "outgoing", eventName, args)
	if RunService:IsClient() then
		self.remoteEvent:FireServer(eventName, table.unpack(args))
	else
		self.remoteEvent:FireAllClients(eventName, table.unpack(args))
	end
end

function Socket:EmitTo(player: Player, eventName: string, ...: any)
	local args = { ... }
	eventName, args = self:_applyMiddleware(self.outgoingMiddleware, "outgoing", eventName, args)
	if RunService:IsClient() then
		error(ERRORS.NOT_SERVER)
	else
		self.remoteEvent:FireClient(player, eventName, table.unpack(args))
	end
end

function Socket:Call(eventName: string, timeout: number?, ...: any)
	if not RunService:IsClient() then
		error(ERRORS.NOT_CLIENT)
	end

	local args = { ... }
	eventName, args = self:_applyMiddleware(self.outgoingMiddleware, "outgoing", eventName, args)

	timeout = timeout or 5

	local requestId = HttpService:GenerateGUID(false)
	local signal = Instance.new("BindableEvent")
	self.pendingRequests[requestId] = signal
	self.remoteEvent:FireServer("CallRequest", eventName, requestId, table.unpack(args))

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
		warn(string.format(ERRORS.CALL_TIMEOUT, eventName, requestId))
		return nil
	end

	return result
end

function Socket:BroadcastExcept(skipPlayers: { Player } | Player, eventName: string, ...: any)
	if RunService:IsClient() then
		error(ERRORS.NOT_SERVER)
	end

	local args = { ... }
	eventName, args = self:_applyMiddleware(self.outgoingMiddleware, "outgoing", eventName, args)

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
			self.remoteEvent:FireClient(p, eventName, table.unpack(args))
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
		error(ERRORS.NOT_SERVER)
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
		error(ERRORS.NOT_SERVER)
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
		error(ERRORS.NOT_SERVER)
	end

	local args = { ... }
	eventName, args = self:_applyMiddleware(self.outgoingMiddleware, "outgoing", eventName, args)

	local room = self.rooms[roomName]
	if not room then
		warn(string.format(ERRORS.NO_ROOM, roomName))
		return
	end
	for _, player in ipairs(room) do
		self.remoteEvent:FireClient(player, eventName, table.unpack(args))
	end
	if self.debug then
		print("[Socket DEBUG] Broadcasted event:", eventName, "to room:", roomName)
	end
end

function Socket:Ping(): number
	if not RunService:IsClient() then
		error(ERRORS.NOT_CLIENT)
	end
	local startTime = tick()
	local pong = self:Call("Ping")
	if pong ~= "Pong" then
		warn(string.format(ERRORS.PING_RESPONSE, tostring(pong)))
	end
	local latency = tick() - startTime
	if self.debug then
		print("[Socket DEBUG] Ping latency:", latency)
	end
	return latency
end

function Socket:ScheduleBroadcast(delay: number, eventName: string, ...: any)
    if RunService:IsClient() then
        error(ERRORS.NOT_SERVER)
    end

    local args = { ... }
    eventName, args = self:_applyMiddleware(self.outgoingMiddleware, "outgoing", eventName, args)

    task.delay(delay, function()
        self.remoteEvent:FireAllClients(eventName, table.unpack(args))
        if self.debug then
            print("[Socket DEBUG] Scheduled broadcast executed for event:", eventName)
        end
    end)

    if self.debug then
        print("[Socket DEBUG] Scheduled broadcast set for event:", eventName, "with delay:", delay)
    end
end

return Socket