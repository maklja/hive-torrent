import Config

config :logger,
  level: :debug,
  # add :console if logs are required in the tests
  backends: [:console]
