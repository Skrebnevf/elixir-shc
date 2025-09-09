# ChatServer

A secure SSL/TLS chat server built with Elixir that supports multiple authenticated clients with real-time message broadcasting.

## Features

- **SSL/TLS Encryption** - All communication is encrypted using self-signed certificates
- **Password Authentication** - SHA256 hashed password authentication for all clients
- **Real-time Broadcasting** - Messages are instantly broadcast to all connected clients
- **Multi-client Support** - Handles multiple concurrent client connections
- **Client Tracking** - Tracks connected clients with IP addresses
- **Process Supervision** - Fault-tolerant with proper supervision trees
- **Certificate Management** - Automatic SSL certificate generation and fingerprint verification

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
  host: {:system, "HOST", :string}
```

For test:

```elixir
config :chatserver, ChatServer.Server,
  port: 4041,
  host: "127.0.0.1"
```

## Usage

### Starting the Server

#### Method 1: With Environment Variable

```bash
export CHAT_SERVER_PASSWORD=mysecretpassword
mix run --no-halt
```

#### Method 2: Interactive Input

```bash
mix run --no-halt
# Enter server password: mysecretpassword

# For Production mode 
MIX_ENV=prod mix run --no-halt
```

### Server Output

When started, the server will display:

```
======================================================================
SERVER CERTIFICATE FINGERPRINT:
a1:b2:c3:d4:e5:f6:78:90:ab:cd:ef:12:34:56:78:90:ab:cd:ef:12:34:56:78:90:ab:cd:ef:12:34:56:78:90

For secure client connections:
export CHAT_SERVER_FINGERPRINT=a1b2c3d4e5f67890abcdef1234567890abcdef1234567890abcdef1234567890

Clients without fingerprint will show security warning
======================================================================

Server password set successfully...
[info] server started on port -> 4000 and ip -> {127, 0, 0, 1}
```

## Protocol

The server uses a custom binary protocol:

### Message Format

```
[4 bytes: message length][N bytes: JSON message data]
```

### Authentication Messages
Client authentication request
```json
{"type": "auth", "password": "user_password"}
```

Server authentication response
```json
{"type": "auth_result", "success": true}
{"type": "auth_result", "success": false, "error": "Invalid password"}
```

### Chat Messages
Client message
```json
{"type": "message", "content": "foo", "sender": "anon"}
```

Server broadcast (includes sender IP)
```json
{"type": "message", "content": "foo", "sender": "anon", "sender_ip": "192.168.1.100"}
```

## SSL Certificates

The server automatically generates self-signed certificates on first run:

- `cert.pem` - SSL certificate
- `key.pem` - Private key
- `server_fingerprint.txt` - Certificate fingerprint for client verification

### Certificate Verification

For secure client connections, clients should verify the server certificate using the displayed fingerprint.

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
- Self-signed certificates (suitable for development/internal use)
- Client IP tracking for monitoring
- Process isolation for fault tolerance

## Production Deployment

For production use:

1. Set strong passwords via environment variables
2. Consider using proper SSL certificates from a CA
3. Configure appropriate firewall rules
4. Monitor server logs for security events
5. Use proper process management (systemd, Docker, etc.)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
