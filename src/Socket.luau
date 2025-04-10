--!strict
--[[
    Socket Module
    ---------------
    A simple socket module for Roblox that allows for reliable and unreliable communication
	between server and client using RemoteEvents and UnreliableRemoteEvents.
	This module provides a clean API for sending and receiving events, as well as middleware
	functionality for modifying event data before it is sent or received.

	https://github.com/OMouta/roblox-sockets
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
    UNRELIABLE_NOT_ENABLED: string,
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
	UNRELIABLE_NOT_ENABLED = "ERR_UNRELIABLE_NOT_ENABLED | Unreliable events are not enabled for this socket.",
}

local Socket = {}
Socket.__index = Socket
Socket.rooms = {}
Socket.version = "0.1.0"

export type ParallelOperation = {
	eventName: string,
	args: {any},
	timeout: number?
}

export type ParallelResult = {
	success: boolean,
	results: {[string]: any?},
	errors: {[string]: string?}
}

export type MiddlewareFunction = (direction: string, eventName: string, args: {any}) -> (string, {any})
export type ListenerCallback = (...any) -> ...any

export type SocketOptions = {
	debug: boolean?,
	unreliable: boolean?
}

export type Socket = {
	remoteEvent: RemoteEvent,
	unreliableRemoteEvent: UnreliableRemoteEvent?,
	listeners: { [string]: {ListenerCallback}? },
	pendingRequests: { [string]: BindableEvent }?,
	debug: boolean,
	unreliable: boolean,
	incomingMiddleware: { MiddlewareFunction },
	outgoingMiddleware: { MiddlewareFunction },
	
	-- Core communication methods
	On: (self: Socket, eventName: string, callback: ListenerCallback) -> (),
	Off: (self: Socket, eventName: string, callback: ListenerCallback?) -> (),
	Once: (self: Socket, eventName: string, callback: ListenerCallback) -> (),
	Emit: (self: Socket, eventName: string, ...any) -> (),
	EmitUnreliable: (self: Socket, eventName: string, ...any) -> (),
	EmitTo: (self: Socket, player: Player, eventName: string, ...any) -> (),
	EmitToUnreliable: (self: Socket, player: Player, eventName: string, ...any) -> (),
	Call: (self: Socket, eventName: string, timeout: number?, ...any) -> any,
	
	-- Middleware methods
	UseIncoming: (self: Socket, middleware: MiddlewareFunction) -> (),
	UseOutgoing: (self: Socket, middleware: MiddlewareFunction) -> (),
	_applyMiddleware: (self: Socket, middlewareList: {MiddlewareFunction}, direction: string, eventName: string, args: {any}) -> (string, {any}),
	
	-- Room functionality
	JoinRoom: (self: Socket, player: Player, roomName: string) -> (),
	LeaveRoom: (self: Socket, player: Player, roomName: string) -> (),
	BroadcastToRoom: (self: Socket, roomName: string, eventName: string, ...any) -> (),
	BroadcastToRoomUnreliable: (self: Socket, roomName: string, eventName: string, ...any) -> (),
	
	-- Broadcasting methods
	BroadcastExcept: (self: Socket, skipPlayers: { Player } | Player, eventName: string, ...any) -> (),
	BroadcastExceptUnreliable: (self: Socket, skipPlayers: { Player } | Player, eventName: string, ...any) -> (),
	ScheduleBroadcast: (self: Socket, delay: number, eventName: string, ...any) -> (),
	
	-- Parallel operations
	EmitParallel: (self: Socket, operations: {ParallelOperation}, strategy: string?) -> ParallelResult,
	CallParallel: (self: Socket, operations: {ParallelOperation}, strategy: string?) -> ParallelResult,
	
	-- Utility methods
	Ping: (self: Socket) -> number,
	initialize: (self: Socket) -> (),
}

function Socket.new(idOrRemoteEvent: any, options: boolean | SocketOptions?): Socket
	local self = setmetatable({}, Socket) :: Socket
	
	-- Handle backwards compatibility with the old debug parameter
	local opts: SocketOptions = {}
	if typeof(options) == "boolean" then
		opts = { debug = options }
	elseif typeof(options) == "table" then
		opts = options
	end
	
	self.debug = opts.debug or false
	self.unreliable = opts.unreliable or false

	self.incomingMiddleware = {}
	self.outgoingMiddleware = {}
	
	-- Always start with fresh handlers regardless of whether we're reusing a RemoteEvent
	self.listeners = {}
	if RunService:IsClient() then
		self.pendingRequests = {}
	end

	if idOrRemoteEvent then
		local t = typeof(idOrRemoteEvent)
		if t == "Instance" then
			if idOrRemoteEvent:IsA("RemoteEvent") then
				self.remoteEvent = idOrRemoteEvent
			elseif idOrRemoteEvent:IsA("UnreliableRemoteEvent") then
				self.unreliableRemoteEvent = idOrRemoteEvent
				self.unreliable = true
				
				-- We still need a reliable RemoteEvent for operations like Call
				local reliableName = idOrRemoteEvent.Name .. "_Reliable"
				local reliableEvent = ReplicatedStorage:FindFirstChild(reliableName)
				if reliableEvent and reliableEvent:IsA("RemoteEvent") then
					self.remoteEvent = reliableEvent
				else
					if RunService:IsClient() then
						error("Cannot create a socket with an UnreliableRemoteEvent without its paired reliable RemoteEvent")
					else
						self.remoteEvent = Instance.new("RemoteEvent")
						self.remoteEvent.Name = reliableName
						self.remoteEvent.Parent = ReplicatedStorage
					end
				end
			end
		elseif t == "string" then
			local eventName = idOrRemoteEvent
			
			-- Set up reliable RemoteEvent
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
			
			-- Set up unreliable RemoteEvent if needed
			if self.unreliable then
				local unreliableName = eventName .. "_Unreliable"
				local unreliableExisting = ReplicatedStorage:FindFirstChild(unreliableName)
				if unreliableExisting and unreliableExisting:IsA("UnreliableRemoteEvent") then
					self.unreliableRemoteEvent = unreliableExisting
				else
					if RunService:IsClient() then
						-- If we're on the client, wait a short time for the server to create the event
						local startTime = tick()
						while not self.unreliableRemoteEvent and (tick() - startTime) < 5 do
							self.unreliableRemoteEvent = ReplicatedStorage:FindFirstChild(unreliableName)
							if self.unreliableRemoteEvent and self.unreliableRemoteEvent:IsA("UnreliableRemoteEvent") then
								break
							end
							self.unreliableRemoteEvent = nil
							task.wait(0.1)
						end
						
						if not self.unreliableRemoteEvent then
							if self.debug then
								warn(string.format("Unreliable remote event '%s' not found. Disabling unreliable mode.", unreliableName))
							end
							self.unreliable = false
						end
					else
						self.unreliableRemoteEvent = Instance.new("UnreliableRemoteEvent")
						self.unreliableRemoteEvent.Name = unreliableName
						self.unreliableRemoteEvent.Parent = ReplicatedStorage
					end
				end
			end
		else
			local eventName = "SocketEvent"
			
			-- Set up reliable RemoteEvent
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
			
			-- Set up unreliable RemoteEvent if needed
			if self.unreliable then
				local unreliableName = eventName .. "_Unreliable"
				local unreliableExisting = ReplicatedStorage:FindFirstChild(unreliableName)
				if unreliableExisting and unreliableExisting:IsA("UnreliableRemoteEvent") then
					self.unreliableRemoteEvent = unreliableExisting
				else
					if RunService:IsClient() then
						-- If we're on the client, wait a short time for the server to create the event
						local startTime = tick()
						while not self.unreliableRemoteEvent and (tick() - startTime) < 5 do
							self.unreliableRemoteEvent = ReplicatedStorage:FindFirstChild(unreliableName)
							if self.unreliableRemoteEvent and self.unreliableRemoteEvent:IsA("UnreliableRemoteEvent") then
								break
							end
							self.unreliableRemoteEvent = nil
							task.wait(0.1)
						end
						
						if not self.unreliableRemoteEvent then
							if self.debug then
								warn(string.format("Unreliable remote event '%s' not found. Disabling unreliable mode.", unreliableName))
							end
							self.unreliable = false
						end
					else
						self.unreliableRemoteEvent = Instance.new("UnreliableRemoteEvent")
						self.unreliableRemoteEvent.Name = unreliableName
						self.unreliableRemoteEvent.Parent = ReplicatedStorage
					end
				end
			end
		end
	else
		local eventName = "SocketEvent"
		
		-- Set up reliable RemoteEvent
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
		
		-- Set up unreliable RemoteEvent if needed
		if self.unreliable then
			local unreliableName = eventName .. "_Unreliable"
			local unreliableExisting = ReplicatedStorage:FindFirstChild(unreliableName)
			if unreliableExisting and unreliableExisting:IsA("UnreliableRemoteEvent") then
				self.unreliableRemoteEvent = unreliableExisting
			else
				if RunService:IsClient() then
					-- If we're on the client, wait a short time for the server to create the event
					local startTime = tick()
					while not self.unreliableRemoteEvent and (tick() - startTime) < 5 do
						self.unreliableRemoteEvent = ReplicatedStorage:FindFirstChild(unreliableName)
						if self.unreliableRemoteEvent and self.unreliableRemoteEvent:IsA("UnreliableRemoteEvent") then
							break
						end
						self.unreliableRemoteEvent = nil
						task.wait(0.1)
					end
					
					if not self.unreliableRemoteEvent then
						if self.debug then
							warn(string.format("Unreliable remote event '%s' not found. Disabling unreliable mode.", unreliableName))
						end
						self.unreliable = false
					end
				else
					self.unreliableRemoteEvent = Instance.new("UnreliableRemoteEvent")
					self.unreliableRemoteEvent.Name = unreliableName
					self.unreliableRemoteEvent.Parent = ReplicatedStorage
				end
			end
		end
	end

	self:initialize()
	return self
end

function Socket:UseIncoming(middleware: MiddlewareFunction)
	table.insert(self.incomingMiddleware, middleware)
end

function Socket:UseOutgoing(middleware: MiddlewareFunction)
	table.insert(self.outgoingMiddleware, middleware)
end

-- Add helper function to process middleware
function Socket:_applyMiddleware(middlewareList: {MiddlewareFunction}, direction: string, eventName: string, args: {any}): (string, {any})
	for _, mw in ipairs(middlewareList) do
		eventName, args = mw(direction, eventName, args)
	end
	return eventName, args
end

function Socket:initialize()
	if RunService:IsClient() then
			-- Store connections so they can be properly cleaned up if needed
			self._connections = self._connections or {}
			
			-- Disconnect any existing connections before creating new ones
			for _, connection in ipairs(self._connections or {}) do
				if typeof(connection) == "RBXScriptConnection" and connection.Connected then
					connection:Disconnect()
				end
			end
			self._connections = {}
			
			-- Set up reliable RemoteEvent handler
			local reliableConnection = self.remoteEvent.OnClientEvent:Connect(function(eventName: string, ...: any)
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
							local success, err = pcall(function()
								callback(table.unpack(args))
							end)
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
			table.insert(self._connections, reliableConnection)
			
			-- Set up unreliable RemoteEvent handler if enabled
			if self.unreliable and self.unreliableRemoteEvent then
				local unreliableConnection = self.unreliableRemoteEvent.OnClientEvent:Connect(function(eventName: string, ...: any)
					local args = { ... }
					eventName, args = self:_applyMiddleware(self.incomingMiddleware, "incoming", eventName, args)
					local callbacks = self.listeners[eventName]
					if callbacks then
						for _, callback in ipairs(callbacks) do
							local success, err = pcall(function()
								callback(table.unpack(args))
							end)
							if not success then
								warn(string.format(ERRORS.CALLBACK_ERROR, "client unreliable", eventName, tostring(err)))
							end
						end
						if self.debug then
							print("[Socket DEBUG] Triggered client unreliable event:", eventName)
						end
					end
				end)
				table.insert(self._connections, unreliableConnection)
			end
		else
			-- Store connections so they can be properly cleaned up if needed
			self._connections = self._connections or {}
			
			-- Disconnect any existing connections before creating new ones
			for _, connection in ipairs(self._connections or {}) do
				if typeof(connection) == "RBXScriptConnection" and connection.Connected then
					connection:Disconnect()
				end
			end
			self._connections = {}
			
			-- Set up reliable RemoteEvent handler
			local reliableConnection = self.remoteEvent.OnServerEvent:Connect(function(player: Player, command: string, ...: any)
				local args = { ... }
				command, args = self:_applyMiddleware(self.incomingMiddleware, "incoming", command, args)
				if command == "CallRequest" then
					local targetEvent, requestId = table.unpack(args)
					local callbacks = self.listeners[targetEvent]
					if not callbacks or #callbacks == 0 then
						warn(string.format(ERRORS.NO_CALL_HANDLER, targetEvent))
					else
						for _, callback in ipairs(callbacks) do
							local success, response = pcall(function()
								return callback(player, select(3, table.unpack(args)))
							end)
							if success then
								self.remoteEvent:FireClient(player, "CallResponse", requestId, response)
							else
								warn(string.format(ERRORS.CALLBACK_ERROR, "server call", targetEvent, tostring(response)))
							end
						end
						if self.debug then
							print("[Socket DEBUG] Processed CallRequest for event:", targetEvent)
						end
					end
				else
					local callbacks = self.listeners[command]
					if callbacks then
						for _, callback in ipairs(callbacks) do
							local success, err = pcall(function()
								callback(player, table.unpack(args))
							end)
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
			table.insert(self._connections, reliableConnection)
			
			-- Set up unreliable RemoteEvent handler if enabled
			if self.unreliable and self.unreliableRemoteEvent then
				local unreliableConnection = self.unreliableRemoteEvent.OnServerEvent:Connect(function(player: Player, command: string, ...: any)
					local args = { ... }
					command, args = self:_applyMiddleware(self.incomingMiddleware, "incoming", command, args)
					local callbacks = self.listeners[command]
					if callbacks then
						for _, callback in ipairs(callbacks) do
							local success, err = pcall(function()
								callback(player, table.unpack(args))
							end)
							if not success then
								warn(string.format(ERRORS.CALLBACK_ERROR, "server unreliable", command, tostring(err)))
							end
						end
						if self.debug then
							print("[Socket DEBUG] Triggered server unreliable event:", command)
						end
					end
				end)
				table.insert(self._connections, unreliableConnection)
			end
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
		return callback(...)
	end
	
	if not self.listeners[eventName] then
		self.listeners[eventName] = {}
	end
	table.insert(self.listeners[eventName], wrapper)
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

function Socket:EmitUnreliable(eventName: string, ...: any)
	if not self.unreliable or not self.unreliableRemoteEvent then
		error(ERRORS.UNRELIABLE_NOT_ENABLED)
	end
	
	local args = { ... }
	eventName, args = self:_applyMiddleware(self.outgoingMiddleware, "outgoing", eventName, args)
	
	if RunService:IsClient() then
		self.unreliableRemoteEvent:FireServer(eventName, table.unpack(args))
	else
		self.unreliableRemoteEvent:FireAllClients(eventName, table.unpack(args))
	end
	
	if self.debug then
		print("[Socket DEBUG] Emitted unreliable event:", eventName)
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

function Socket:EmitToUnreliable(player: Player, eventName: string, ...: any)
	if RunService:IsClient() then
		error(ERRORS.NOT_SERVER)
	end
	
	if not self.unreliable or not self.unreliableRemoteEvent then
		error(ERRORS.UNRELIABLE_NOT_ENABLED)
	end
	
	local args = { ... }
	eventName, args = self:_applyMiddleware(self.outgoingMiddleware, "outgoing", eventName, args)
	
	self.unreliableRemoteEvent:FireClient(player, eventName, table.unpack(args))
	
	if self.debug then
		print("[Socket DEBUG] Emitted unreliable event to", player.Name, ":", eventName)
	end
end

function Socket:Call(eventName: string, timeout: number?, ...: any): any
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

function Socket:BroadcastExceptUnreliable(skipPlayers: { Player } | Player, eventName: string, ...: any)
	if RunService:IsClient() then
		error(ERRORS.NOT_SERVER)
	end
	
	if not self.unreliable or not self.unreliableRemoteEvent then
		error(ERRORS.UNRELIABLE_NOT_ENABLED)
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
			self.unreliableRemoteEvent:FireClient(p, eventName, table.unpack(args))
		end
	end
	
	if self.debug then
		local names = {}
		for _, player in ipairs(playersToSkip) do
			table.insert(names, player.Name)
		end
		print("[Socket DEBUG] Broadcasted unreliable event:", eventName, "to all except", table.concat(names, ", "))
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

function Socket:BroadcastToRoomUnreliable(roomName: string, eventName: string, ...: any)
	if RunService:IsClient() then
		error(ERRORS.NOT_SERVER)
	end
	
	if not self.unreliable or not self.unreliableRemoteEvent then
		error(ERRORS.UNRELIABLE_NOT_ENABLED)
	end
	
	local args = { ... }
	eventName, args = self:_applyMiddleware(self.outgoingMiddleware, "outgoing", eventName, args)
	
	local room = self.rooms[roomName]
	if not room then
		warn(string.format(ERRORS.NO_ROOM, roomName))
		return
	end
	
	for _, player in ipairs(room) do
		self.unreliableRemoteEvent:FireClient(player, eventName, table.unpack(args))
	end
	
	if self.debug then
		print("[Socket DEBUG] Broadcasted unreliable event:", eventName, "to room:", roomName)
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

function Socket:EmitParallel(operations: {ParallelOperation}, strategy: string?): ParallelResult
	if not operations or #operations == 0 then
		return {
			success = false,
			results = {},
			errors = { ["error"] = "No operations provided" }
		}
	end
	
	strategy = strategy or "all" -- Default strategy: wait for all operations
	
	if RunService:IsServer() then
		-- Server implementation of parallel emit
		local results: {[string]: any} = {}
		local errors: {[string]: string} = {}
		local success = true
		
		for i, operation in ipairs(operations) do
			local eventName, args = operation.eventName, operation.args or {}
			eventName, args = self:_applyMiddleware(self.outgoingMiddleware, "outgoing", eventName, args)
			
			-- Since server's Emit is synchronous, we can just call it directly
			local status, err = pcall(function()
				self.remoteEvent:FireAllClients(eventName, table.unpack(args))
			end)
			
			if not status then
				success = false
				errors[eventName] = tostring(err)
				if strategy == "all" then
					-- If strategy is "all", one failure means overall failure
					break
				end
			else
				results[eventName] = true
				if strategy == "any" or strategy == "race" then
					-- If strategy is "any" or "race", one success means we can stop
					break
				end
			end
		end
		
		return {
			success = success,
			results = results,
			errors = errors
		}
	else
		-- Client implementation of parallel emit
		local results: {[string]: any} = {}
		local errors: {[string]: string} = {}
		local success = true
		local pending = #operations
		local completed = false
		
		local function checkCompletion(): boolean
			if strategy == "all" then
				-- All operations must succeed
				return pending == 0
			elseif strategy == "any" then
				-- At least one operation must succeed
				return next(results) ~= nil
			elseif strategy == "race" then
				-- The first operation to complete (success or failure) determines the result
				return next(results) ~= nil or next(errors) ~= nil
			end
			return pending == 0
		end
		
		for i, operation in ipairs(operations) do
			local eventName, args = operation.eventName, operation.args or {}
			eventName, args = self:_applyMiddleware(self.outgoingMiddleware, "outgoing", eventName, args)
			
			-- Fire the event asynchronously
			task.spawn(function()
				local emitSuccess, err = pcall(function()
					self.remoteEvent:FireServer(eventName, table.unpack(args))
				end)
				
				if emitSuccess then
					results[eventName] = true
				else
					errors[eventName] = tostring(err)
				end
				
				pending -= 1
				
				if checkCompletion() and not completed then
					completed = true
				end
			end)
		end
		
		-- Wait for completion or timeout
		local startTime = tick()
		local maxTimeout = 5 -- Default timeout
		
		-- Find the maximum timeout among all operations
		for _, operation in ipairs(operations) do
			if operation.timeout and operation.timeout > maxTimeout then
				maxTimeout = operation.timeout
			end
		end
		
		-- Wait loop
		while not completed and (tick() - startTime) < maxTimeout do
			task.wait(0.05)
		end
		
		-- Handle timeout
		if not completed then
			for _, operation in ipairs(operations) do
				if not results[operation.eventName] and not errors[operation.eventName] then
					errors[operation.eventName] = "Timed out"
				end
			end
		end
		
		-- Determine overall success based on strategy
		if strategy == "all" then
			success = next(errors) == nil
		elseif strategy == "any" then
			success = next(results) ~= nil
		elseif strategy == "race" then
			success = next(results) ~= nil
		end
		
		return {
			success = success,
			results = results,
			errors = errors
			}
		end
	end

-- Execute multiple socket calls in parallel
function Socket:CallParallel(operations: {ParallelOperation}, strategy: string?): ParallelResult
	if RunService:IsServer() then
		error(ERRORS.NOT_CLIENT)
	end
	
	if not operations or #operations == 0 then
		return {
			success = false,
			results = {},
			errors = { ["error"] = "No operations provided" }
		}
	end
	
	strategy = strategy or "all" -- Default strategy: wait for all operations
	
	local results: {[string]: any} = {}
	local errors: {[string]: string} = {}
	local success = true
	local pendingCalls = #operations
	local completed = false
	
	local function checkCompletion(): boolean
		if strategy == "all" then
			-- All operations must succeed
			return pendingCalls == 0
		elseif strategy == "any" then
			-- At least one operation must succeed
			return next(results) ~= nil
		elseif strategy == "race" then
			-- The first operation to complete (success or failure) determines the result
			return next(results) ~= nil or next(errors) ~= nil
		end
		return pendingCalls == 0
	end
	
	for i, operation in ipairs(operations) do
		local eventName, args = operation.eventName, operation.args or {}
		local timeout = operation.timeout or 5
		
		-- Process middleware
		eventName, args = self:_applyMiddleware(self.outgoingMiddleware, "outgoing", eventName, args)
		
		-- Execute the call asynchronously
		task.spawn(function()
			local requestId = HttpService:GenerateGUID(false)
			local signal = Instance.new("BindableEvent")
			self.pendingRequests[requestId] = signal
			
			-- Fire the call request
			self.remoteEvent:FireServer("CallRequest", eventName, requestId, table.unpack(args))
			
			local startTime = tick()
			local fired = false
			local result = nil
			
			local connection = signal.Event:Connect(function(value)
				result = value
				fired = true
			end)
			
			-- Wait for response or timeout
			repeat
				task.wait(0.05)
			until fired or (tick() - startTime) >= timeout
			
			connection:Disconnect()
			self.pendingRequests[requestId] = nil
			
			if fired then
				results[eventName] = result
			else
				errors[eventName] = string.format(ERRORS.CALL_TIMEOUT, eventName, requestId)
			end
			
			pendingCalls -= 1
			
			if checkCompletion() and not completed then
				completed = true
			end
		end)
	end
	
	-- Find the maximum timeout among all operations
	local maxTimeout = 5 -- Default timeout
	for _, operation in ipairs(operations) do
		if operation.timeout and operation.timeout > maxTimeout then
			maxTimeout = operation.timeout
		end
	end
	
	-- Wait loop
	local startTime = tick()
	while not completed and (tick() - startTime) < maxTimeout do
		task.wait(0.05)
	end
	
	-- Handle timeout for any remaining operations
	if not completed then
		for _, operation in ipairs(operations) do
			if not results[operation.eventName] and not errors[operation.eventName] then
				errors[operation.eventName] = "Timed out"
			end
		end
	end
	
	-- Determine overall success based on strategy
	if strategy == "all" then
		success = next(errors) == nil
	elseif strategy == "any" then
		success = next(results) ~= nil
	elseif strategy == "race" then
		success = next(results) ~= nil
	end
	
	return {
		success = success,
		results = results,
		errors = errors
	}
end

return Socket