defmodule ChatServer.ClientSupervisor do
  @moduledoc """
  A dynamic supervisor for managing individual chat client processes.

  This supervisor handles the lifecycle of client connection processes,
  automatically starting new processes for each connecting client and
  cleaning up when clients disconnect.

  ## Supervision Strategy
  Uses `:one_for_one` strategy where:
  - Each client process is supervised independently
  - If a client process crashes, only that client is restarted
  - Other client processes remain unaffected

  ## Child Process Configuration
  Client processes are configured as:
  - **Restart**: `:temporary` - processes are not restarted if they terminate
  - **ID**: `ChatServer.ClientHandler` - identifier for the child spec
  - **Start**: Calls `ChatServer.ClientHandler.start_link/1` with the socket

  This configuration is appropriate for client connections because:
  - Client disconnections are normal and expected
  - Crashed client processes shouldn't be automatically restarted
  - Each client manages its own socket lifecycle

  ## Usage
  The supervisor is typically started as part of the main application
  supervision tree and used by the main server to spawn client processes:

      # Start a new client process
      {:ok, client_pid} = ClientSupervisor.start_client(ssl_socket)

  ## Integration
  This supervisor works with:
  - `ChatServer.Server` - calls `start_client/1` for new connections
  - `ChatServer.ClientHandler` - the actual client process implementation
  - `ChatServer.Application` - includes this supervisor in the supervision tree

  ## Process Lifecycle
  1. Server accepts new SSL connection
  2. Server calls `ClientSupervisor.start_client(socket)`
  3. Supervisor starts new `ClientHandler` process
  4. Client process handles authentication and messaging
  5. When client disconnects, process terminates and is removed automatically

  No manual cleanup is required as the supervisor handles process lifecycle
  management automatically.
  """

  use DynamicSupervisor

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_client(socket) do
    spec = %{
      id: ChatServer.ClientHandler,
      start: {ChatServer.ClientHandler, :start_link, [socket]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
