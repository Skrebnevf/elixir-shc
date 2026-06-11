defmodule ChatServer.ServerTest do
  use ExUnit.Case, async: false

  @port 4041
  @host ~c"127.0.0.1"
  @password "test_password"
  @password_hash :crypto.hash(:sha256, @password) |> Base.encode64()

  setup context do
    Application.put_env(:chatserver, :password_hash, @password_hash)
    max = context[:max_global_connections] || 300

    children = [
      ChatServer.ClientRegistry,
      {DynamicSupervisor, strategy: :one_for_one, name: ChatServer.ClientSupervisor},
      {ChatServer.Server, port: @port, host: "127.0.0.1", max_global_connections: max}
    ]

    {:ok, sup_pid} = Supervisor.start_link(children, strategy: :one_for_one)
    :timer.sleep(300)

    on_exit(fn ->
      Process.exit(sup_pid, :shutdown)
      :timer.sleep(100)
    end)

    :ok
  end


  defp connect_client do
    {:ok, socket} =
      :ssl.connect(@host, @port, [:binary, packet: :raw, active: false, verify: :verify_none],
        :timer.seconds(5)
      )

    socket
  end

  defp auth_client(socket, password, username) do
    msg = %{"type" => "auth", "password" => password, "username" => username}
    :ssl.send(socket, ChatServer.Protocol.encode_message(msg))
    recv_msg(socket)
  end

  defp send_chat(socket, content, sender) do
    msg = %{"type" => "message", "content" => content, "sender" => sender}
    :ssl.send(socket, ChatServer.Protocol.encode_message(msg))
  end

  defp recv_msg(socket, timeout \\ 2_000) do
    case :ssl.recv(socket, 4, timeout) do
      {:ok, <<size::32>>} when size > 0 ->
        case :ssl.recv(socket, size, timeout) do
          {:ok, data} -> {:ok, Jason.decode!(data)}
          error -> error
        end

      other ->
        other
    end
  end

  # ── tests ────────────────────────────────────────

  test "server accepts SSL connections" do
    socket = connect_client()
    assert socket != nil
    :ssl.close(socket)
  end

  test "successful authentication" do
    socket = connect_client()
    assert {:ok, resp} = auth_client(socket, @password_hash, "test_user")
    assert resp["success"] == true
    :ssl.close(socket)
  end

  test "failed authentication returns error" do
    socket = connect_client()
    assert {:ok, resp} = auth_client(socket, "wrong_hash", "attacker")
    assert resp["success"] == false
    assert resp["error"] == "Invalid password"
    :ssl.close(socket)
  end

  test "failed authentication introduces ~1 s delay" do
    socket = connect_client()

    auth_data =
      ChatServer.Protocol.encode_message(%{
        "type" => "auth",
        "password" => "wrong_hash",
        "username" => "hacker"
      })

    :ssl.send(socket, auth_data)

    assert {:ok, resp} = recv_msg(socket)
    assert resp["success"] == false

    {duration, _} =
      :timer.tc(fn ->
        assert {:error, _} = :ssl.recv(socket, 4, 5_000)
      end)

    assert duration >= 900_000
    :ssl.close(socket)
  end

  test "messages are broadcast to other clients" do
    alice = connect_client()
    bob = connect_client()

    assert {:ok, _} = auth_client(alice, @password_hash, "alice")
    assert {:ok, _} = auth_client(bob, @password_hash, "bob")

    send_chat(alice, "hello from alice", "alice")

    assert {:ok, msg} = recv_msg(bob)
    assert msg["content"] == "hello from alice"
    assert msg["sender"] == "alice"

    :ssl.close(alice)
    :ssl.close(bob)
  end

  test "sender does not receive own message" do
    alice = connect_client()
    bob = connect_client()

    assert {:ok, _} = auth_client(alice, @password_hash, "alice")
    assert {:ok, _} = auth_client(bob, @password_hash, "bob")

    send_chat(alice, "secret", "alice")
    assert {:ok, _} = recv_msg(bob, 2_000)
    assert :ssl.recv(alice, 4, 500) == {:error, :timeout}

    :ssl.close(alice)
    :ssl.close(bob)
  end

  test "multiple clients receive broadcast" do
    alice = connect_client()
    bob = connect_client()
    carol = connect_client()

    assert {:ok, _} = auth_client(alice, @password_hash, "alice")
    assert {:ok, _} = auth_client(bob, @password_hash, "bob")
    assert {:ok, _} = auth_client(carol, @password_hash, "carol")

    send_chat(alice, "group message", "alice")

    assert {:ok, msg_bob} = recv_msg(bob)
    assert {:ok, msg_carol} = recv_msg(carol)
    assert msg_bob["content"] == "group message"
    assert msg_carol["content"] == "group message"

    :ssl.close(alice)
    :ssl.close(bob)
    :ssl.close(carol)
  end

  @tag max_global_connections: 2
  test "global limit below per-IP limit is respected" do
    sockets =
      Enum.map(1..2, fn i ->
        s = connect_client()
        assert {:ok, resp} = auth_client(s, @password_hash, "user_#{i}")
        assert resp["success"] == true
        s
      end)

    third = connect_client()
    :timer.sleep(200)

    auth_data =
      ChatServer.Protocol.encode_message(%{
        "type" => "auth",
        "password" => @password_hash,
        "username" => "user_3"
      })

    case :ssl.send(third, auth_data) do
      :ok ->
        assert {:error, _} = recv_msg(third, 2_000)

      {:error, _reason} ->
        :ok
    end

    Enum.each(sockets, &:ssl.close/1)
    :ssl.close(third)
  end

  test "limits connections to 10 per IP" do
    sockets =
      Enum.map(1..10, fn i ->
        s = connect_client()
        assert {:ok, resp} = auth_client(s, @password_hash, "user_#{i}")
        assert resp["success"] == true
        s
      end)

    # 11th — handshake succeeds but server closes the socket immediately
    eleventh = connect_client()
    :timer.sleep(200)
    auth_data = ChatServer.Protocol.encode_message(%{"type" => "auth", "password" => @password_hash, "username" => "user_11"})

    case :ssl.send(eleventh, auth_data) do
      :ok ->
        assert {:error, _} = recv_msg(eleventh, 2_000)

      {:error, _reason} ->
        :ok
    end

    Enum.each(sockets, &:ssl.close/1)
    :ssl.close(eleventh)
  end

  defp assert_server_alive do
    socket = connect_client()
    assert {:ok, resp} = auth_client(socket, @password_hash, "probe")
    assert resp["success"] == true
    :ssl.close(socket)
  end

  test "server certificate has valid SHA256 fingerprint" do
    socket = connect_client()

    {:ok, cert_der} = :ssl.peercert(socket)

    fingerprint = :crypto.hash(:sha256, cert_der) |> Base.encode16(case: :lower)

    assert String.match?(fingerprint, ~r/^[a-f0-9]{64}$/)

    assert File.exists?("server_fingerprint.txt")
    {:ok, file_content} = File.read("server_fingerprint.txt")
    assert file_content =~ fingerprint

    :ssl.close(socket)
  end

  test "wrong password attempt does not crash server, valid connections still work" do
    attacker = connect_client()
    assert {:ok, resp} = auth_client(attacker, "wrong_hash", "attacker")
    assert resp["success"] == false
    assert resp["error"] == "Invalid password"

    valid = connect_client()
    assert {:ok, resp2} = auth_client(valid, @password_hash, "valid_user")
    assert resp2["success"] == true

    :ssl.close(attacker)
    :ssl.close(valid)
  end

  test "connection with ssl verification enabled rejects self-signed cert" do
    result =
      :ssl.connect(@host, @port,
        [:binary, packet: :raw, active: false, verify: :verify_peer, depth: 2],
        :timer.seconds(5)
      )

    assert match?({:error, _}, result)
  end

  test "oversized message does not crash server" do
    client = connect_client()
    assert {:ok, _} = auth_client(client, @password_hash, "alice")

    :ssl.send(client, <<0, 1, 0, 1>>)
    :timer.sleep(300)

    assert_server_alive()
  end

  test "size=0 message after auth does not crash server" do
    chatty = connect_client()
    assert {:ok, _} = auth_client(chatty, @password_hash, "talker")

    :ssl.send(chatty, <<0, 0, 0, 0>>)
    :timer.sleep(200)

    assert_server_alive()
    :ssl.close(chatty)
  end

  test "non-auth JSON before auth does not crash server" do
    client = connect_client()

    msg = ChatServer.Protocol.encode_message(%{"type" => "message", "content" => "hi"})
    :ssl.send(client, msg)
    :timer.sleep(300)

    assert_server_alive()
  end

  test "binary garbage before auth does not crash server" do
    client = connect_client()

    :ssl.send(client, <<0, 0, 0, 6, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF>>)
    :timer.sleep(300)

    assert_server_alive()
  end

  test "invalid UTF-8 bytes inside valid size does not crash server" do
    client = connect_client()
    assert {:ok, _} = auth_client(client, @password_hash, "alice")

    :ssl.send(client, <<0, 0, 0, 5, 0xFF, 0xFE, 0xFD, 0xFC, 0xFB>>)
    :timer.sleep(200)

    assert_server_alive()
    :ssl.close(client)
  end

  test "disconnected client during broadcast does not crash server" do
    alice = connect_client()
    bob = connect_client()

    assert {:ok, _} = auth_client(alice, @password_hash, "alice")
    assert {:ok, _} = auth_client(bob, @password_hash, "bob")

    :ssl.close(bob)
    :timer.sleep(100)

    send_chat(alice, "ping", "alice")
    :timer.sleep(200)

    assert_server_alive()
    :ssl.close(alice)
  end

  test "rapid connect/disconnect does not deplete resources" do
    1..25
    |> Enum.each(fn i ->
      s = connect_client()
      assert {:ok, resp} = auth_client(s, @password_hash, "rapid_#{i}")
      assert resp["success"] == true
      :ssl.close(s)
    end)

    :timer.sleep(200)
    assert_server_alive()
  end

  @tag max_global_connections: 3
  test "exact global limit (3) + 1 rejected keeps server alive" do
    sockets =
      1..3
      |> Enum.map(fn i ->
        s = connect_client()
        assert {:ok, resp} = auth_client(s, @password_hash, "limit_#{i}")
        assert resp["success"] == true
        s
      end)

    fourth = connect_client()
    :timer.sleep(200)
    auth_data =
      ChatServer.Protocol.encode_message(%{
        "type" => "auth",
        "password" => @password_hash,
        "username" => "limit_4"
      })

    case :ssl.send(fourth, auth_data) do
      :ok -> assert {:error, _} = recv_msg(fourth, 2_000)
      {:error, _reason} -> :ok
    end

    :ssl.close(fourth)

    Enum.each(sockets, &:ssl.close/1)
    :timer.sleep(200)
    assert_server_alive()
  end

  test "auth with empty username does not break server" do
    client = connect_client()

    msg = ChatServer.Protocol.encode_message(%{
      "type" => "auth",
      "password" => @password_hash,
      "username" => ""
    })
    :ssl.send(client, msg)

    assert {:ok, resp} = recv_msg(client)
    assert resp["success"] == true
    :ssl.close(client)

    assert_server_alive()
  end

  test "double auth message treated as broadcast, server stays up" do
    alice = connect_client()
    bob = connect_client()

    assert {:ok, _} = auth_client(alice, @password_hash, "alice")
    assert {:ok, _} = auth_client(bob, @password_hash, "bob")

    second_auth = ChatServer.Protocol.encode_message(%{
      "type" => "auth",
      "password" => @password_hash,
      "username" => "alice"
    })
    :ssl.send(alice, second_auth)

    assert {:ok, msg} = recv_msg(bob, 2_000)
    assert msg["type"] == "auth"
    assert msg["username"] == "alice"

    send_chat(alice, "still works", "alice")
    assert {:ok, msg2} = recv_msg(bob, 2_000)
    assert msg2["content"] == "still works"

    :ssl.close(alice)
    :ssl.close(bob)
  end

  test "auth missing type field is caught by catch-all" do
    client = connect_client()

    msg = ChatServer.Protocol.encode_message(%{
      "password" => @password_hash,
      "username" => "attacker"
    })
    :ssl.send(client, msg)
    :timer.sleep(200)

    assert_server_alive()
  end

  test "auth missing password field is caught by catch-all" do
    client = connect_client()

    msg = ChatServer.Protocol.encode_message(%{
      "type" => "auth",
      "username" => "attacker"
    })
    :ssl.send(client, msg)
    :timer.sleep(200)

    assert_server_alive()
  end

  test "auth missing username field is caught by catch-all" do
    client = connect_client()

    msg = ChatServer.Protocol.encode_message(%{
      "type" => "auth",
      "password" => @password_hash
    })
    :ssl.send(client, msg)
    :timer.sleep(200)

    assert_server_alive()
  end

  test "exact max size message (65536 bytes) does not crash server" do
    client = connect_client()
    assert {:ok, _} = auth_client(client, @password_hash, "alice")

    body = String.duplicate("A", 65536)
    header = <<65536::32>>
    :ssl.send(client, header <> body)
    :timer.sleep(200)

    assert_server_alive()
    :ssl.close(client)
  end

  test "raw TCP connection rejected by SSL server" do
    {:ok, tcp_socket} =
      :gen_tcp.connect(~c"127.0.0.1", @port, [:binary, packet: :raw, active: false],
        :timer.seconds(5)
      )

    :timer.sleep(200)
    assert_server_alive()
    :gen_tcp.close(tcp_socket)
  end
end
