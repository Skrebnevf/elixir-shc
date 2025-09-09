import Config

config :chatserver, ChatServer.Server,
  port: 4040,
  host: "127.0.0.1"

import_config "#{config_env()}.exs"
