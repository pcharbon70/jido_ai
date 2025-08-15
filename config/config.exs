import Config

config :logger, :console,
  format: {Jido.AI.Keyring.Filter, :format},
  metadata: [:module]

# Test environment - suppress debug logs during tests
if Mix.env() == :test do
  config :logger, level: :warning
end
