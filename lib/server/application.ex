defmodule ChatServer.Application do
  @moduledoc """
  The main application module for ChatServer that starts the supervision tree
  and handles password configuration.

  This application automatically configures the server password on startup using
  one of two methods:
  1. Environment variable `CHAT_SERVER_PASSWORD`
  2. Interactive password input from stdin

  The password is hashed using SHA256 and stored in the application environment
  for use by the chat server.

  ## Supervision Tree
  The application starts the following supervised processes:
  - `ChatServer.ClientRegistry` - Registry for tracking connected clients
  - `DynamicSupervisor` (ClientSupervisor) - Supervises individual client processes
  - `ChatServer.Server` - The main SSL chat server

  ## Password Configuration

  ### Environment Variable (Recommended)
      export CHAT_SERVER_PASSWORD=mysecretpassword
      mix run --no-halt

  ### Interactive Input
  If no environment variable is set, the application will prompt for password input:
      Enter server password:

  ### Docker/Non-Interactive Environments
  In environments where stdin is not available, you must use the environment variable.
  The application will halt with an error message if neither method is available.

  ## Example Usage
      # Set password via environment
      CHAT_SERVER_PASSWORD=mypass mix run --no-halt

      # Or let it prompt interactively
      mix run --no-halt
      # Enter server password: mypass

  The application uses a `:one_for_one` supervision strategy, meaning if any
  child process crashes, only that process will be restarted.
  """
  use Application

  @impl true
  def start(_type, _args) do
    password = get_password_safely()
    password_hash = :crypto.hash(:sha256, password) |> Base.encode64()
    Application.put_env(:chatserver, :password_hash, password_hash)
    IO.puts("Server password set successfully...")

    children = [
      ChatServer.ClientRegistry,
      {DynamicSupervisor, strategy: :one_for_one, name: ChatServer.ClientSupervisor},
      ChatServer.Server
    ]

    opts = [strategy: :one_for_one, name: ChatServer.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp get_password_safely do
    case System.get_env("CHAT_SERVER_PASSWORD") do
      nil ->
        try_interactive_input()

      password ->
        IO.puts("Using password from environment variable\n")
        password
    end
  end

  defp try_interactive_input do
    case :io.get_line(:standard_io, "Enter server password: ") do
      {:error, :enotsup} ->
        fallback_password("stdin not supported")

      {:error, :ebadf} ->
        fallback_password("stdin not available")

      {:error, reason} ->
        fallback_password("input error: #{inspect(reason)}\n")

      password when is_list(password) ->
        password |> List.to_string() |> String.trim()

      password when is_binary(password) ->
        String.trim(password)
    end
  end

  defp fallback_password(reason) do
    IO.puts(:stderr, "Cannot read password interactively: \n#{reason}\n")
    IO.puts(:stderr, "Please set CHAT_SERVER_PASSWORD environment variable\n")
    IO.puts(:stderr, "Example: CHAT_SERVER_PASSWORD=mypass mix run --no-halt\n")
    System.halt(1)
  end
end
