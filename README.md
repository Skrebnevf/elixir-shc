# ChatServer

A secure SSL/TLS chat server built with Elixir that supports multiple authenticated clients with real-time message broadcasting.

## Features

- **SSL/TLS Encryption** - All communication is encrypted using self-signed certificates
- **Password Authentication** - SHA256 hashed password authentication for all clients
- **Real-time Broadcasting** - Messages are instantly broadcast to all connected clients
- **Multi-client Support** - Handles multiple concurrent client connections
- **Client Tracking** - Tracks connected clients with IP addresses
- **Process Supervision** - Fault-tolerant with proper supervision trees
- **Rate Limiting** - Protections against abuse: 1-second delay on failed auth, per-IP connection limit (10), global connection limit (300), and mailbox overflow protection
- **Certificate Auto-Regeneration** - SSL certificates are recreated fresh on every server start, old files are cleaned up
- **No Persistent Storage** - All data lives in memory; server leaves no trace on disk after shutdown

## Architecture

The server is built using Elixir's OTP (Open Telecom Platform) principles:

- **GenServer** - Main server process handling client connections and message routing
- **Registry** - Client tracking and metadata storage
- **DynamicSupervisor** - Dynamic supervision of client processes
- **Custom Protocol** - Binary protocol with JSON messages for reliable communication

## Installation

1. Clone the repository:

```bash
git clone https://github.com/skrebnevf/elixir-shc.git
cd elixir-shc
```

2. Install dependencies:

```bash
mix deps.get
```

3. Compile the project:

```bash
mix compile
```

## Configuration

### Environment Variables

For production deployments, use environment variables:

```elixir
config :chatserver, ChatServer.Server,
  port: {:system, "PORT", :integer},
  host: {:system, "HOST", :string},
  max_global_connections: {:system, "MAX_CLIENTS", :integer}
```

Set the maximum number of simultaneous clients:

```bash
export MAX_CLIENTS=500
```

For test:

```elixir
config :chatserver, ChatServer.Server,
  port: 4041,
  host: "127.0.0.1",
  max_global_connections: 300
```

For development (`config/config.exs`):

```elixir
config :chatserver, ChatServer.Server,
  port: 4040,
  host: "127.0.0.1",
  max_global_connections: 300
```

## Usage

### Starting the Server

#### Method 1: Using the Launch Script (Recommended)

```bash
export CHAT_SERVER_PASSWORD=mysecretpassword
./bin/server
```

The `bin/server` script passes the correct VM flags for Ctrl+C handling
and cleans up certificate files on exit.

#### Method 2: With Environment Variable

```bash
export CHAT_SERVER_PASSWORD=mysecretpassword
mix run --no-halt
```

#### Method 3: Interactive Input

```bash
mix run --no-halt
# Enter server password: mysecretpassword
```

> In non-interactive environments (Docker, CI) you **must** use the
> `CHAT_SERVER_PASSWORD` environment variable. If neither is available,
> the server will exit with an error.

### Server Output

When started, the server will display:

```
Enter server password:
Server password set successfully...

======================================================================
SERVER CERTIFICATE FINGERPRINT:
a1:b2:c3:d4:e5:f6:78:90:ab:cd:ef:12:34:56:78:90:ab:cd:ef:12:34:56:78:90:ab:cd:ef:12:34:56:78:90

For secure client connections:
export CHAT_SERVER_FINGERPRINT=a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890

Clients without fingerprint will show security warning
======================================================================

[info] server started on port -> 4000 and ip -> {127, 0, 0, 1}
```

## Protocol

The server uses a custom binary protocol:

### Message Format

```
[4 bytes: message length][N bytes: JSON message data]
```

### Authentication Messages
Client authentication request (username is required; password is SHA256 hash encoded in Base64)
```json
{"type": "auth", "password": "m0Hx7RfmTM3sJ0x7Jh2M0Hx7RfmTM3sJ0x7Jh2M0Hx7Rg=", "username": "alice"}
```

Server authentication response
```json
{"type": "auth_result", "success": true}
{"type": "auth_result", "success": false, "error": "Invalid password"}
```

### Chat Messages
Client message
```json
{"type": "message", "content": "foo", "sender": "alice"}
```

Server broadcast (same format, relayed to all other clients)
```json
{"type": "message", "content": "foo", "sender": "alice"}
```

> The server relays messages as-is without modifying the content or adding fields.

## SSL Certificates

The server automatically generates fresh self-signed certificates on **every** start. Old files (`cert.pem`, `key.pem`, `server_fingerprint.txt`) are deleted and recreated — each server instance has a unique fingerprint.

### Certificate Verification

The displayed fingerprint allows **clients** to verify the server's identity. The server itself does not enforce fingerprint checking — it's up to each client to verify the fingerprint before sending sensitive data. Note that the fingerprint changes after each server restart.

When connecting without verification, OpenSSL will show a security warning on the client side.

## Development

### Running Tests

```bash
mix test
```

### Code Formatting

```bash
mix format
```

### Documentation

```bash
mix docs
```

## Requirements

- Elixir 1.18+
- Erlang/OTP 24+
- OpenSSL (for certificate generation)

## Security Considerations

- Uses SHA256 for password hashing
- All communication is encrypted with SSL/TLS
- 1-second delay on failed authentication (prevents brute-force)
- Per-IP connection limit (10 connections per IP)
- Global connection limit (configurable, default 300)
- Mailbox overflow protection (drops messages when queue exceeds 1000)
- Self-signed certificates regenerated on every start
- Process isolation for fault tolerance
- No persistent storage — all data is in-memory

## Production Deployment

For production use:

1. Set strong passwords via environment variables
2. Configure connection limits with `MAX_CLIENTS` environment variable
3. Consider using proper SSL certificates from a trusted CA
4. Configure appropriate firewall rules
5. Monitor server logs for security events
6. Use proper process management (systemd, Docker, etc.)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
