defmodule ChatServerTest do
  use ExUnit.Case
  doctest Chatapp

  test "greets the world" do
    assert Chatapp.hello() == :world
  end
end
