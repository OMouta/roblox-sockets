local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Socket = require(ReplicatedStorage:WaitForChild("Socket"))
local socket = Socket.new(nil, true)

socket:UseIncoming(function(direction, eventName, args)
    print("[Client Middleware Incoming]", direction, eventName, table.concat(
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
    print("[Client Middleware Outgoing]", direction, eventName, table.concat(
        (function()
            local t = {}
            for i, v in ipairs(args) do
                t[i] = tostring(v)
            end
            return t
        end)(), ", "))
    return eventName, args
end)

socket:On("HelloFromServer", function(message)
    print("Client received welcome message:", message)
end)

socket:On("TargetedMessage", function(message)
    print("Client received targeted message:", message)
end)

socket:On("StateUpdate", function(newState)
    print("Client received state update:", newState)
end)

socket:Emit("HelloFromClient", "Hi Server, this is the client!")

local serverTime = socket:Call("GetServerTime")
print("Client received server time:", serverTime)

local result = socket:Call("DoesNotExist", 3, "arg1", "arg2")
if result then
    print("Received response:", result)
else
    print("Timed out!")
end

local player = Players.LocalPlayer
socket:Emit("RequestTargetedMessage", player.Name)

local latency = socket:Ping()
print("Client measured latency (seconds):", latency)

socket:Emit("UpdateState", math.random(1, 10))

socket:Emit("RequestJoinRoom", "TestRoom")

socket:On("RoomJoined", function(roomName)
    print("Joined room:", roomName)
end)

socket:On("RoomLeft", function(roomName)
    print("Left room:", roomName)
end)

socket:On("RoomMessage", function(sender, message)
    print("Message from", sender, "in room:", message)
end)

socket:Emit("MessageRoom", "TestRoom", "Hello, room!")