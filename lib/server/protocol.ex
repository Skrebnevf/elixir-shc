defmodule ChatServer.Protocol do
  @moduledoc """
  Handles message encoding, decoding, and transmission protocol for the chat server.

  This module implements a simple binary protocol for reliable message transmission
  over SSL connections. Messages are JSON-encoded and prefixed with a 4-byte
  length header to ensure complete message reception.

  # Encode a message
  message = %{"type" => "chat", "content" => "Hello!"}
  binary_data = Protocol.encode_message(message)

  # Send over SSL socket
  :ssl.send(socket, binary_data)

  # Receive a message
  {:ok, received_message} = Protocol.recv_message(socket)
  """

  @max_packet_size 65536

  def encode_message(data) do
    json_data = Jason.encode!(data)

    if byte_size(json_data) > @max_packet_size do
      raise "Message too large! #{byte_size(json_data)} bytes"
    end

    size = byte_size(json_data)
    <<size::32>> <> json_data
  end

  def recv_message(socket) do
    with {:ok, <<size::32>>} <- :ssl.recv(socket, 4),
         {:ok, json_data} <- :ssl.recv(socket, size) do
      {:ok, Jason.decode!(json_data)}
    end
  end
end
