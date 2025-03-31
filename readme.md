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
