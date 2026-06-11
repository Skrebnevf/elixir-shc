defmodule ChatServer.ClientSupervisor do
  @moduledoc """
  A dynamic supervisor for managing individual chat client processes.

  This supervisor handles the lifecycle of client connection processes,
  automatically starting new processes for each connecting client. Since
  clients use `:temporary` restart strategy, terminated processes are
  **not** restarted — this is intentional: disconnections are normal.

  ## Supervision Strategy
  Uses `:one_for_one` strategy where each client process is supervised
  independently. A crash in one client does **not** affect others.

  ## Child Process Configuration
  Client processes are started via `DynamicSupervisor.start_child/2`
  from `ChatServer.Server`. Each child uses:
  - **Restart**: `:temporary` — never restarted after termination
  - **Implementation**: `Task.start/1` — lightweight process running
    `client_loop/2` which handles auth and messaging

  ## Usage

  The supervisor is started as part of the main supervision tree by
  `ChatServer.Application`. `ChatServer.Server` spawns client processes
  through it:

      child_spec = %{
        id: :client_process,
        start: {Task, :start, [fn -> client_loop(socket, hash) end]},
        restart: :temporary
      }
      DynamicSupervisor.start_child(ChatServer.ClientSupervisor, child_spec)

  ## Process Lifecycle
  1. `ChatServer.Server.accept_loop/3` accepts new SSL connection
  2. Server builds a child spec with `Task.start` and passes it to
     `DynamicSupervisor.start_child/2`
  3. Client process runs `client_loop/2`: handles auth → `message_loop/1`
  4. On disconnect or error, the process terminates with `exit(:normal)`
  5. DynamicSupervisor removes the terminated child automatically

  No manual cleanup is required — the DynamicSupervisor handles all
  lifecycle management.
  """

  use DynamicSupervisor

  def start_link(_opts) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
