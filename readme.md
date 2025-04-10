# Socket Module

**Disclaimer:** Roblox does not natively support sockets. This module provides a socket-like interface built on top of Roblox's RemoteEvents for client-server communication.

The Socket module provides an event-based interface for client–server communication using RemoteEvents. It is designed with features similar to socket.io and has been extended to support:

- **Multiple Channels**: Create independent sockets by passing an identifier.  
  • If a string is provided, the corresponding RemoteEvent will be used (or created on the server).  
  • If a RemoteEvent is provided, it is used directly.  
  • If `nil` is passed, the module falls back to the default (`SocketEvent`).

- **Event Listening**: Register event listeners using `On`, remove them with `Off`, or listen only once with `Once`.

- **Event Emission**:
  - Use `Emit` to send events to the server (from client) or to all clients (from the server).
  - Use `EmitTo` for targeted messaging (server only).

- **Remote Procedure Calls**: The `Call` method enables clients to call server-side functions and wait for a response with a timeout mechanism.

- **Broadcasting**:
  - `BroadcastExcept` lets the server send an event to all players except a specified one.
  - `BroadcastToRoom` (and room management functions) allow broadcasting to a subset of players who have joined a specified room/channel.

- **Middleware/Interceptors**:  
  – Use `UseIncoming` and `UseOutgoing` to inject custom processing hooks for filtering, transforming, or logging event data before it is transmitted or handled.

- **Latency Measurement**: The `Ping` method measures the client-to-server latency.

---

## Features and Usage Examples

### 1. Creating Sockets on Different Channels

You can now create multiple sockets that listen on specific RemoteEvents by passing an identifier.

**Server Example:**

````lua
local Socket = require(ReplicatedStorage:WaitForChild("Socket"))
-- Create a socket for the Chat channel
local chatSocket = Socket.new("ChatChannel", true)
````

**Client Example:**

````lua
local Socket = require(ReplicatedStorage:WaitForChild("Socket"))
-- Connect to the Chat channel (make sure the server has created it)
local chatSocket = Socket.new("ChatChannel", true)
````

If you pass `nil` as the identifier, the module uses the default RemoteEvent named `"SocketEvent"`.

### 2. Event Listening and Emission

**Listening:**

On the client:

````lua
socket:On("HelloFromServer", function(message)
    print("Client received:", message)
end)
````

On the server:

````lua
socket:On("HelloFromClient", function(player, message)
    print("Server received from", player.Name, ":", message)
end)
````

**Emitting:**

Client emitting to server:

````lua
socket:Emit("HelloFromClient", "Hi Server, this is the client!")
````

Server broadcasting to clients:

````lua
socket:Emit("HelloFromServer", "Welcome to the game!")
````

For targeted messaging (server only), use:

````lua
socket:EmitTo(targetPlayer, "TargetedMessage", "Hello from the server")
````

### 3. Remote Procedure Calls (Call)

Clients can call server functions and wait for a response:

**Client:**

````lua
local serverTime = socket:Call("GetServerTime")
print("Client received server time:", serverTime)
````

**Server:**

````lua
socket:On("GetServerTime", function(player)
    return os.time()  -- Return the server time
end)
````

### 4. Broadcasting with Exception and Room/Channel Management

**Broadcasting to all players except one:**

````lua
socket:BroadcastExcept(player, "StateUpdate", newState)
````

**Room Management:**

Add players to a room and broadcast messages only to that room.

_Server API:_

````lua
socket:On("RequestJoinRoom", function(player, roomName)
    socket:JoinRoom(player, roomName)
    socket:EmitTo(player, "RoomJoined", roomName)
end)

socket:On("MessageRoom", function(player, roomName, message)
    socket:BroadcastToRoom(roomName, "RoomMessage", player.Name, message)
end)
````

_Client side:_

````lua
socket:Emit("RequestJoinRoom", "TestRoom")

socket:On("RoomJoined", function(roomName)
    print("Joined room:", roomName)
end)

socket:On("RoomMessage", function(sender, message)
    print("Message from", sender, "in room:", message)
end)

socket:Emit("MessageRoom", "TestRoom", "Hello, room!")
````

### 5. Middleware/Interceptors

You can register middleware functions to process event data before sending or after receiving.

**Example (Logging Middleware):**

_On both client and server:_

````lua
socket:UseOutgoing(function(direction, eventName, args)
    print("[Middleware - Outgoing]", eventName, unpack(args))
    return eventName, args  -- Optionally transform or filter
end)

socket:UseIncoming(function(direction, eventName, args)
    print("[Middleware - Incoming]", eventName, unpack(args))
    return eventName, args
end)
````

### 6. Measuring Latency

Clients can measure the latency by using:

````lua
local latency = socket:Ping()
print("Client measured latency (seconds):", latency)
````

### 7. Scheduled Broadcasts

The `ScheduleBroadcast` method allows the server to schedule a broadcast to all clients after a specified delay.

**Server Example:**

````lua
socket:ScheduleBroadcast(10, "EventName", "This message will be broadcasted after 10 seconds.")
````

**Client Example:**

Clients can listen for the scheduled broadcast:

````lua
socket:On("EventName", function(message)
    print("Received scheduled message:", message)
end)
````

**Test Example:**

A test case has been added to demonstrate this feature:

- The server listens for a `ScheduledBroadcastTest` event and schedules a broadcast.
- The client emits the `ScheduledBroadcastTest` event with a delay and message.

**Server Test:**

````lua
socket:On("ScheduledBroadcastTest", function(player, delay, message)
    socket:ScheduleBroadcast(delay, "ScheduledBroadcast", message)
end)
````

**Client Test:**

````lua
socket:Emit("ScheduledBroadcastTest", 5, "This is a scheduled message!")
````

### 8. Parallel Socket Operations

The Socket module now supports parallel operations with both `EmitParallel` and `CallParallel` methods. These allow multiple socket operations to be executed concurrently, with different resolution strategies:

- **all**: All operations must succeed for the overall result to be successful
- **any**: At least one operation must succeed for the overall result to be successful
- **race**: The first operation to complete (success or failure) determines the result

#### Parallel Calls (Client-side)

```lua
local result = socket:CallParallel({
    {
        eventName = "Event1",
        args = {"Arg1", "Arg2"},
        timeout = 5 -- Optional timeout in seconds
    },
    {
        eventName = "Event2",
        args = {"Arg1", "Arg2"},
        timeout = 3
    }
}, "all") -- Strategy: can be "all", "any", or "race"

print("Overall success:", result.success)

-- Check individual results
for eventName, response in pairs(result.results) do
    print("Success for", eventName, ":", response)
end

-- Check individual errors
for eventName, errorMsg in pairs(result.errors) do
    print("Error for", eventName, ":", errorMsg)
end
```

#### Parallel Emissions (Server-side)

```lua
local result = socket:EmitParallel({
    {
        eventName = "Event1",
        args = {"Message1"}
    },
    {
        eventName = "Event2",
        args = {"Message2"}
    }
}, "all") -- Strategy: can be "all", "any", or "race"

print("All emissions successful:", result.success)
```

#### Benefits of Parallel Operations

- **Improved Efficiency**: Execute multiple network operations simultaneously
- **Fault Tolerance**: Continue even if some operations fail (with "any" strategy)
- **Race Conditions**: Get the fastest result first (with "race" strategy)
- **Timeout Handling**: Each operation can have its own timeout
- **Comprehensive Results**: Get detailed success/failure information for each operation

**Test Example:**

Client-side test showing how to use parallel operations and handle the results:

```lua
local parallelResult = socket:CallParallel({
    {
        eventName = "FastOperation",
        args = {"Fast data"},
        timeout = 5
    },
    {
        eventName = "SlowOperation",
        args = {"Slow data"},
        timeout = 3 -- Will timeout if the operation takes longer
    }
}, "any") -- We only need one to succeed

if parallelResult.success then
    print("At least one operation succeeded!")
else
    print("All operations failed!")
end
```

### 9. Unreliable Event Transmission

The Socket module now supports unreliable event transmission through UnreliableRemoteEvent instances. Unreliable events are perfect for frequent, non-critical updates where occasional packet loss is acceptable in exchange for reduced network overhead.

#### Setting Up Unreliable Mode

Enable unreliable mode when creating a socket by passing options:

```lua
local socket = Socket.new("MyChannel", { 
    debug = true,       -- Optional debug mode
    unreliable = true   -- Enable unreliable events support
})
```

This creates both a reliable RemoteEvent and an unreliable UnreliableRemoteEvent. For backward compatibility, you can also use the old debug parameter:

```lua
-- Legacy way - only sets debug mode, no unreliable support
local socket = Socket.new("MyChannel", true)

-- New way - full options support
local socket = Socket.new("MyChannel", { debug = true, unreliable = true })
```

#### Using Unreliable Events

Once unreliable mode is enabled, you can use the following methods:

**Unreliable Emit Methods**:

```lua
-- Client-to-server or server-to-all-clients unreliable transmission
socket:EmitUnreliable("PlayerPosition", position)

-- Server-to-specific-client unreliable transmission
socket:EmitToUnreliable(player, "EnemyPosition", enemyPosition)

-- Server broadcasts to all players except specified ones
socket:BroadcastExceptUnreliable(player, "OtherPlayerPositions", positions)

-- Server broadcasts to players in a specific room
socket:BroadcastToRoomUnreliable("GameRoom", "GameState", gameState)
```

#### When to Use Unreliable Events

Unreliable transmission is ideal for:

- Frequent position updates (player movements, projectiles)
- Visual effects that aren't gameplay-critical
- Temporary state information that's quickly superseded
- High-frequency sensor data or telemetry
- Any data where occasional packet loss is acceptable

Example: Player Position Updates

```lua
-- Server side
socket:On("UnreliablePosition", function(player, position)
    -- Process player position
    -- Broadcast to other players in the same area
    for _, otherPlayer in ipairs(playersInArea) do
        if otherPlayer ~= player then
            socket:EmitToUnreliable(otherPlayer, "OtherPlayerPosition", player.UserId, position)
        end
    end
end)

-- Client side
local function updatePlayerPosition()
    while true do
        local position = character:GetPrimaryPartCFrame().Position
        socket:EmitUnreliable("UnreliablePosition", position)
        task.wait(0.1) -- Send position 10 times per second
    end
end
```

This implementation greatly reduces network traffic for high-frequency updates while maintaining gameplay experience.

---

## Module Overview (Socket.luau)

The Socket module abstracts Roblox RemoteEvents to create a familiar socket-like interface with the following functionalities:

- **On/Off/Once APIs** for registering and removing event callbacks.
- **Emit/EmitTo APIs** to send events to one or many clients.
- **Call API** for remote function calls with a timeout.
- **BroadcastExcept and room management APIs** for targeted event broadcasting.
- **UseIncoming and UseOutgoing** functions to configure middleware for custom event data processing.
- **Optional RemoteEvent identifier** support for multiple communication channels.

Happy coding!
