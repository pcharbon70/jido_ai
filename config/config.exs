import Config

alias Jido.AI.Keyring.Filter

config :logger, :console,
  format: {Filter, :format},
  metadata: [:module]

# Test environment - suppress debug logs during tests
if Mix.env() == :test do
  config :logger, level: :warning
end
