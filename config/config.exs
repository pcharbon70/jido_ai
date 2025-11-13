import Config

config :logger, :console,
  format: {Jido.AI.Keyring.Filter, :format},
  metadata: [
    :module,
    :action_module,
    :exception,
    :duration_ms,
    :reason,
    :error,
    :provider,
    :conversation_id,
    :successes,
    :failures,
    :tool_choice,
    :functions,
    :table,
    :ttl,
    :cleanup_interval,
    :deleted,
    :remaining
  ]

# ReqLLM configuration
config :req_llm,
  # Enable automatic model sync from models.dev
  auto_sync: true,
  # Default request timeout in milliseconds
  timeout: 60_000,
  # Default number of retries for failed requests
  retries: 3
