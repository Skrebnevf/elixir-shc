defmodule ChatServer.Server do
  @moduledoc """
  A GenServer-based SSL chat server that handles multiple authenticated clients
  and broadcasts messages between them.

  The server provides secure communication using SSL/TLS encryption and requires
  password authentication for all clients. Messages sent by one client are
  broadcast to all other connected clients.

  ## Configuration
  Configure the server in your application config:
      config :chatserver, ChatServer.Server,
        port: 4000,
        host: "localhost"

      config :chatserver,
        password_hash: "base64_encoded_sha256_hash_of_password"

  Runtime configuration is supported using system environment variables:
      config :chatserver, ChatServer.Server,
        port: {:system, "PORT", :integer},
        host: {:system, "HOST", :string}

  ## SSL Certificates
  The server automatically generates or uses existing SSL certificates through
  the `CertificateManager` module.

  ## Client Flow
  1. Client connects via SSL
  2. Client sends authentication message with password
  3. Server verifies password hash
  4. On success, client is registered and can send/receive messages
  5. All messages are broadcast to other connected clients

  ## Example
      # Start the server
      {:ok, _pid} = ChatServer.Server.start_link(port: 8080, host: "0.0.0.0")

  The server will automatically handle client connections, authentication,
  and message broadcasting.
  """
  alias ChatServer.ClientRegistry
  alias ChatServer.CertificateManager
  alias ChatServer.Protocol
  alias ChatServer.ClientSupervisor
  require Logger
  use GenServer

  def start_link(opts \\ []) do
    config = Application.get_env(:chatserver, __MODULE__, [])

    port = get_config_value(Keyword.get(opts, :port, config[:port]))
    host = get_config_value(Keyword.get(opts, :host, config[:host]))

    GenServer.start_link(__MODULE__, {host, port}, name: __MODULE__)
  end

  def init({host, port}) do
    Process.flag(:trap_exit, true)

    {cert_file, key_file} = CertificateManager.ensure_certificates(host)
    password_hash = Application.get_env(:chatserver, :password_hash)

    bind_ip =
      :inet.getaddr(to_charlist(host), :inet)
      |> case do
        {:ok, ip} -> ip
        {:error, _} -> {0, 0, 0, 0}
      end

    {:ok, listen_socket} =
      :ssl.listen(port, [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: bind_ip,
        certfile: cert_file,
        keyfile: key_file
      ])

    Logger.info("server started on port -> #{port} and ip -> #{inspect(bind_ip)}")

    {:ok, %{listen_socket: listen_socket, password_hash: password_hash},
     {:continue, :accept_loop}}
  end

  def handle_continue(:accept_loop, state) do
    spawn_link(fn -> accept_loop(state.listen_socket, state.password_hash) end)
    {:noreply, state}
  end

  def handle_cast({:message, sender_pid, msg}, state) do
    sender_ip =
      case Registry.lookup(ClientRegistry, sender_pid) do
        [{_pid, %{ip: ip}}] -> ip
        [] -> "unknown"
      end

    message_data = Map.put(msg, "sender_ip", sender_ip)
    encoded_message = Protocol.encode_message(message_data)

    ClientRegistry.get_all_clients()
    |> Enum.each(fn {client_pid, %{socket: client_socket}} ->
      if client_pid != sender_pid do
        :ssl.send(client_socket, encoded_message)
      end
    end)

    {:noreply, state}
  end

  def handle_info({:DOWN, _monitor_ref, :process, client_pid, reason}, state) do
    client_info =
      case Registry.lookup(ClientRegistry, client_pid) do
        [{_pid, %{ip: ip}}] -> ip
        [] -> "unknown"
      end

    Logger.info("Client disconnected",
      ip: client_info,
      reason: reason,
      remaining_clients: length(ClientRegistry.get_all_clients()) - 1
    )

    {:noreply, state}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    Logger.warning("Process #{inspect(pid)} died: #{inspect(reason)}")
    {:noreply, state}
  end

  def terminate(reason, state) do
    Logger.warning("Shutting down server, reason: #{inspect(reason)}")
    :ssl.close(state.listen_socket)
    :ok
  end

  defp get_config_value({:system, env_var, :integer}),
    do:
      get_env!(env_var)
      |> String.to_integer()

  defp get_config_value({:system, env_var, :string}) do
    get_env!(env_var)
  end

  defp get_config_value(value), do: value

  defp get_env!(env) do
    case System.get_env(env) do
      nil -> raise "Missing vars HOST or PORT #{env}"
      value -> value
    end
  end

  defp accept_loop(listen_socket, password_hash) do
    case :ssl.transport_accept(listen_socket) do
      {:ok, socket} ->
        case :ssl.handshake(socket) do
          {:ok, ssl_socket} ->
            Logger.info("New client connected, waiting for auth...")

            child_spec = %{
              id: :client_process,
              start: {Task, :start_link, [fn -> client_loop(ssl_socket, password_hash) end]},
              restart: :temporary
            }

            case DynamicSupervisor.start_child(ClientSupervisor, child_spec) do
              {:ok, _pid} ->
                accept_loop(listen_socket, password_hash)

              {:error, reason} ->
                Logger.warning("Failed to start client process: #{inspect(reason)}")
                :ssl.close(ssl_socket)
                accept_loop(listen_socket, password_hash)
            end

          {:error, reason} ->
            Logger.warning("SSL handshake failed: #{inspect(reason)}")
            :ssl.close(socket)
            accept_loop(listen_socket, password_hash)
        end

      {:error, :closed} ->
        Logger.warning("Listen socket closing")
        :ok

      {:error, _} = err ->
        Logger.warning("Accept error: #{inspect(err)}")
        :timer.sleep(1000)
        accept_loop(listen_socket, password_hash)
    end
  end

  defp client_loop(socket, password_hash) do
    case :ssl.peername(socket) do
      {:ok, {ip, _port}} ->
        readable_ip = :inet.ntoa(ip) |> to_string()

        case Protocol.recv_message(socket) do
          {:ok, %{"type" => "auth", "password" => client_password}} ->
            client_password_hash =
              :crypto.hash(:sha256, client_password)
              |> Base.encode64()

            if client_password_hash == password_hash do
              ClientRegistry.register_client(socket, readable_ip)
              auth_response = %{"type" => "auth_result", "success" => true}
              :ssl.send(socket, Protocol.encode_message(auth_response))
              Logger.info("Client authenticated successfully from #{readable_ip}")
              message_loop(socket)
            else
              auth_response = %{
                "type" => "auth_result",
                "success" => false,
                "error" => "Invalid password"
              }

              :ssl.send(socket, Protocol.encode_message(auth_response))
              Logger.warning("Authentication failed for client #{readable_ip}")
              :ssl.close(socket)
              exit(:normal)
            end

          {:error, reason} ->
            Logger.warning(
              "Failed to receive auth from client #{readable_ip}: #{inspect(reason)}"
            )

            :ssl.close(socket)
            exit(:normal)
        end

      {:error, reason} ->
        Logger.warning("Client connected with unknown IP: #{inspect(reason)}")
        :ssl.close(socket)
        exit(:normal)
    end
  end

  defp message_loop(socket) do
    case Protocol.recv_message(socket) do
      {:ok, message} ->
        GenServer.cast(__MODULE__, {:message, self(), message})
        message_loop(socket)

      {:error, :closed} ->
        Logger.warning("Client disconnected")
        :ssl.close(socket)
        exit(:normal)
    end
  end
end
