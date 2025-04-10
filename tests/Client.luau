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

socket:Emit("ScheduledBroadcastTest", 5, "This is a scheduled message!")

socket:On("HelloFromServer", function(message)
	print("Client received welcome message:", message)
end)

socket:On("TargetedMessage", function(message)
	print("Client received targeted message:", message)
end)

socket:On("StateUpdate", function(newState)
	print("Client received state update:", newState)
end)

socket:On("ScheduledBroadcast", function(message)
    print("Client received scheduled broadcast message:", message)
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

-- Test parallel operations
socket:On("ParallelResponse1", function(data)
    print("Client received ParallelResponse1:", data)
end)

socket:On("ParallelResponse2", function(data)
    print("Client received ParallelResponse2:", data)
end)

-- Test CallParallel
print("\nTesting CallParallel with 'all' strategy:")
local parallelCallResult = socket:CallParallel({
    {
        eventName = "ParallelTest1",
        args = {"Test data 1"},
        timeout = 5
    },
    {
        eventName = "ParallelTest2",
        args = {"Test data 2"},
        timeout = 5
    }
}, "all")

print("CallParallel 'all' result:", parallelCallResult.success)
for eventName, result in pairs(parallelCallResult.results) do
    print("  Event:", eventName, "Result:", result)
end

if next(parallelCallResult.errors) then
    for eventName, err in pairs(parallelCallResult.errors) do
        print("  Error in event:", eventName, "Error:", err)
    end
end

-- Test CallParallel with a mix of fast and slow operations
print("\nTesting CallParallel with 'any' strategy (including a slow operation):")
local mixedCallResult = socket:CallParallel({
    {
        eventName = "ParallelTest1",
        args = {"Fast test"},
        timeout = 5
    },
    {
        eventName = "ParallelTest3",
        args = {"Slow test"},
        timeout = 3 -- Timeout before the slow operation completes
    }
}, "any")

print("CallParallel 'any' result:", mixedCallResult.success)
for eventName, result in pairs(mixedCallResult.results) do
    print("  Event:", eventName, "Result:", result)
end

if next(mixedCallResult.errors) then
    for eventName, err in pairs(mixedCallResult.errors) do
        print("  Error in event:", eventName, "Error:", err)
    end
end

-- Test server EmitParallel through a Call
print("\nTesting server EmitParallel through a Call:")
local serverEmitResult = socket:Call("EmitParallelTest", "all")
print("Server EmitParallel call result:", serverEmitResult and serverEmitResult.success)

-- Create a dedicated unreliable socket for testing high-frequency updates
local unreliableSocket = Socket.new("PositionSocket", { debug = true, unreliable = true })

-- Listen for position updates from other players
unreliableSocket:On("PlayerPositionUpdate", function(playerName, position)
    print("Received position update from", playerName, ":", position)
end)

unreliableSocket:On("RoomPositionUpdate", function(playerName, position)
    print("Received room position update from", playerName, ":", position)
end)

unreliableSocket:On("RoomJoinedUnreliable", function(roomName)
    print("Joined unreliable room:", roomName)
end)

-- Simulate frequent position updates that would benefit from unreliable transmission
local function simulatePositionUpdates()
    local player = Players.LocalPlayer
    local position = Vector3.new(0, 0, 0)
    
    print("Starting unreliable position update simulation...")
    
    -- Send several position updates using unreliable transmission (mimics high-frequency movement data)
    for i = 1, 5 do
        position = Vector3.new(math.random(-100, 100), math.random(0, 50), math.random(-100, 100))
        print("Sending unreliable position update:", position)
        unreliableSocket:EmitUnreliable("UnreliableEvent", position)
        task.wait(0.2) -- Short delay between updates (5 times per second)
    end
    
    -- Join a room for more targeted position updates
    local roomName = "PositionRoom"
    print("Joining unreliable position update room:", roomName)
    unreliableSocket:Emit("UnreliableRoomTest", roomName, Vector3.new(0, 10, 0))
    
    -- Wait for room join acknowledgment
    task.wait(0.5)
    
    -- Send position updates to the room (mimics gameplay where positions only matter to players in the same area)
    for i = 1, 3 do
        position = Vector3.new(math.random(-100, 100), math.random(0, 50), math.random(-100, 100))
        print("Sending position update to room:", position)
        unreliableSocket:EmitUnreliable("UpdateRoomPosition", roomName, position)
        task.wait(0.2)
    end
    
    print("Unreliable position update simulation completed")
end

-- Run the position update simulation in a separate thread
task.spawn(simulatePositionUpdates)