defmodule ChatServer.ClientRegistry do
  @moduledoc """
  A registry for tracking connected chat clients and their associated metadata.

  This module wraps Elixir's built-in Registry to provide a simple interface
  for registering chat clients and retrieving information about all connected
  clients. Each client process registers itself with its socket and IP address.

  The registry uses `:unique` keys, meaning each process can only register once,
  and the process PID serves as the unique identifier.

  ## Client Data Structure
  Each registered client stores the following metadata:
  - `socket` - The SSL socket for communication
  - `ip` - The client's IP address as a string

  ## Usage
  ### Registration
  Client processes register themselves after successful authentication:

      # Usually called from within the client process
      ClientRegistry.register_client(ssl_socket, "192.168.1.100")

  ### Retrieving Clients
  Get all connected clients for message broadcasting:

      clients = ClientRegistry.get_all_clients()
      # Returns: [{pid1, %{socket: socket1, ip: "192.168.1.100"}}, ...]

  ## Registry Structure
  The underlying Registry uses the following structure:
  - **Keys**: `:unique` - each process can register only once
  - **Key**: Process PID (automatically set by `self()`)
  - **Value**: Map with `%{socket: ssl_socket, ip: ip_string}`

  ## Automatic Cleanup
  Since Registry is linked to registered processes, when a client process
  terminates (due to disconnection or crash), it is automatically removed
  from the registry without manual cleanup.

  ## Integration
  This registry is typically used by:
  - `ChatServer.Server` - for message broadcasting and client lookup
  - Client processes - for self-registration after authentication
  - Monitoring processes - for tracking connection statistics
  """

  def start_link(_opts) do
    Registry.start_link(keys: :unique, name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def register_client(socket, ip, username) do
    Registry.register(__MODULE__, self(), %{socket: socket, ip: ip, username: username})
  end

  def get_all_clients do
    Registry.select(__MODULE__, [
      {{:"$1", :"$2", :"$3"}, [], [{{:"$2", :"$3"}}]}
    ])
  end
end
