import Config

config :chatserver, ChatServer.Server,
  port: 4040,
  host: "127.0.0.1",
  max_global_connections: 300

import_config "#{config_env()}.exs"
