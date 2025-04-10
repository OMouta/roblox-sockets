local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Socket = require(ReplicatedStorage:WaitForChild("Socket"))
local socket = Socket.new(nil, true)

socket:UseIncoming(function(direction, eventName, args)
	print("[Server Middleware Incoming]", direction, eventName, table.concat(
		(function()
			local t = {}
			for i, v in ipairs(args) do
				t[i] = tostring(v)
			end
			return t
		end)(), ", "))
	return eventName, args
end)

socket:UseOutgoing(function(direction, eventName, args)
	print("[Server Middleware Outgoing]", direction, eventName, table.concat(
		(function()
			local t = {}
			for i, v in ipairs(args) do
				t[i] = tostring(v)
			end
			return t
		end)(), ", "))
	return eventName, args
end)

socket:On("ScheduledBroadcastTest", function(player, delay, message)
    print("Server received scheduled broadcast request from", player.Name, "with delay:", delay, "and message:", message)
    socket:ScheduleBroadcast(delay, "ScheduledBroadcast", message)
end)

socket:On("HelloFromClient", function(player, message)
	print("Server received from", player.Name, ":", message)
	socket:Emit("HelloFromServer", "Hello, " .. player.Name .. "!")
end)

socket:On("GetServerTime", function(player)
	local serverTime = os.time()
	print("Providing server time to", player.Name)
	return serverTime
end)

socket:On("RequestTargetedMessage", function(player, targetPlayerName)
	local targetPlayer = Players:FindFirstChild(targetPlayerName)
	if targetPlayer then
		socket:EmitTo(targetPlayer, "TargetedMessage", "Hello from " .. player.Name)
	else
		warn("Target player " .. targetPlayerName .. " not found!")
	end
end)

socket:On("Ping", function(player)
	return "Pong"
end)

socket:On("UpdateState", function(player, state)
	print("Sending state update from", player.Name)
	socket:BroadcastExcept(player, "StateUpdate", state)
end)

socket:On("RequestJoinRoom", function(player, roomName)
	socket:JoinRoom(player, roomName)
	socket:EmitTo(player, "RoomJoined", roomName)
end)

socket:On("RequestLeaveRoom", function(player, roomName)
	socket:LeaveRoom(player, roomName)
	socket:EmitTo(player, "RoomLeft", roomName)
end)

socket:On("MessageRoom", function(player, roomName, message)
	print(player.Name, "is sending message to room", roomName, ":", message)
	socket:BroadcastToRoom(roomName, "RoomMessage", player.Name, message)
end)

-- Test for parallel operations
socket:On("ParallelTest1", function(player, data)
    print("Server received ParallelTest1 from", player.Name, ":", data)
    return "Response1"
end)

socket:On("ParallelTest2", function(player, data)
    print("Server received ParallelTest2 from", player.Name, ":", data)
    return "Response2"
end)

socket:On("ParallelTest3", function(player, data)
    -- Simulate a slow operation
    task.wait(2)
    print("Server received ParallelTest3 from", player.Name, ":", data)
    return "Response3"
end)

socket:On("EmitParallelTest", function(player, strategy)
    print("Server testing EmitParallel with strategy:", strategy)
    
    local operations = {
        {
            eventName = "ParallelResponse1",
            args = {"Server EmitParallel test 1"}
        },
        {
            eventName = "ParallelResponse2",
            args = {"Server EmitParallel test 2"}
        }
    }
    
    local result = socket:EmitParallel(operations, strategy)
    print("Server EmitParallel result:", result.success)
    
    -- Return the result to the client
    return result
end)

-- Create a dedicated unreliable socket on the server with a UNIQUE name
local unreliableSocket = Socket.new("PositionSocket", { debug = true, unreliable = true })

-- Test for unreliable events
unreliableSocket:On("UnreliableEvent", function(player, position)
    print("Server received unreliable position update from", player.Name, ":", position)
    
    -- Broadcast this position to all other players using unreliable transmission
    unreliableSocket:BroadcastExceptUnreliable(player, "PlayerPositionUpdate", player.Name, position)
end)

unreliableSocket:On("UnreliableRoomTest", function(player, roomName, position)
    print("Server received room join request from", player.Name, "for room:", roomName)
    
    -- Add player to the room if not already there
    unreliableSocket:JoinRoom(player, roomName)
    print("Player", player.Name, "joined room:", roomName)
    
    -- Acknowledge room join to the player
    unreliableSocket:EmitTo(player, "RoomJoinedUnreliable", roomName)
    
    -- If position data was provided, broadcast it to the room
    if position then
        print("Broadcasting position update to room:", roomName)
        unreliableSocket:BroadcastToRoomUnreliable(roomName, "RoomPositionUpdate", player.Name, position)
    end
end)

-- Handle room position updates separately
unreliableSocket:On("UpdateRoomPosition", function(player, roomName, position)
    print("Server received room position update from", player.Name, "in room:", roomName)
    -- Broadcast only to players in the same room using unreliable transmission
    unreliableSocket:BroadcastToRoomUnreliable(roomName, "RoomPositionUpdate", player.Name, position)
end)