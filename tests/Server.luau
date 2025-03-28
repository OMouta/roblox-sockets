local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Socket = require(ReplicatedStorage:WaitForChild("Socket"))
local socket = Socket.new(nil, true)

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