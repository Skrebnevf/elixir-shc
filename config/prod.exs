import Config

config :chatserver, ChatServer.Server,
  port: {:system, "PORT", :integer},
  host: {:system, "HOST", :string}
