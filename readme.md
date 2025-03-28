# Socket Module

The Socket module provides a simple, event-based interface for client-server communication
in Roblox, similar to socket.io. It wraps around RemoteEvents and offers the following key features:

- **Event Listening**: Register event listeners using `On`, remove them with `Off`, or listen only once with `Once`.
- **Event Emission**: Use `Emit` to send events to all clients (from the server) or to the server (from the client). Use `EmitTo` for targeted messaging (server only).
- **Remote Procedure Calls**: The `Call` method allows a client to call a server function and wait for a response within a timeout.
- **Broadcasting**: `BroadcastExcept` lets the server send an event to all players except one.
- **Latency measurement**: The `Ping` method helps measure client-to-server latency.

---

## Features and Usage Examples

### 1. Event Listening

Register event callbacks on both sides using `On`.  
Example (client-side):

````lua
socket:On("HelloFromServer", function(message)
    print("Client received:", message)
end)
````

On the server side:

````lua
socket:On("HelloFromClient", function(player, message)
    print("Server received from", player.Name, ":", message)
end)
````

### 2. Emitting Events

Use `Emit` to send events.  
Example (client emitting to server):

````lua
socket:Emit("HelloFromClient", "Hi Server, this is the client!")
````

On the server, you can broadcast to all clients:

````lua
socket:Emit("HelloFromServer", "Welcome to the game!")
````

For targeted messaging (server only), use `EmitTo`:

````lua
socket:EmitTo(targetPlayer, "TargetedMessage", "Hello from server")
````

### 3. Remote Procedure Calls (Call)

Clients can call server functions and await a response:

````lua
local serverTime = socket:Call("GetServerTime")
print("Client received server time:", serverTime)
````

On the server, handle the call like a normal event:

````lua
socket:On("GetServerTime", function(player)
    return os.time()  -- Returning the server time
end)
````

### 4. Broadcasting with Exception

The server can broadcast an event to all players except one using `BroadcastExcept`:

````lua
socket:BroadcastExcept(player, "StateUpdate", newState)
````

### 5. Measuring Latency

Measure the ping from client to server with the `Ping` method:

````lua
local latency = socket:Ping()
print("Client measured latency (seconds):", latency)
````

---

## Module Overview (Socket.luau)

The Socket module abstracts Roblox RemoteEvents to create a familiar socket-like interface.
It supports:

- **On/Off/Once APIs**: For registering and removing callbacks.
- **Emit/EmitTo APIs**: To send events both broadly and in a targeted manner.
- **Call API**: To perform remote procedure calls with automatic timeout handling.
- **BroadcastExcept API**: To send events to all players except a specified one.
- **Ping API**: To measure client-server latency.

For more detailed usage, inspect the code samples in Client.luau and Server.luau.

Happy coding!
