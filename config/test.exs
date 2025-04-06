import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :pii_monitor, PiiMonitorWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "7EKsrbWAneDXsZiJgZbz1/Pv8VNOvl5Ii7rBut6QFDKXWcOf817K+vo6ZC+z3m2G",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime
