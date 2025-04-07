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