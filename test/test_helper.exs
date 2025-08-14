# Import Mimic globally for HTTP mocking

# Configure test exclusions
ExUnit.configure(
  exclude: [
    # Exclude integration tests by default
    :integration,
    # Exclude slow tests by default  
    :slow,
    # Exclude tests that hit real APIs
    :external_api,
    # Exclude flaky tests by default
    :flaky
  ]
)

ExUnit.start()

# Set up global test verification - removed problematic verify_on_exit

# Require test support files
Code.require_file("support/test_utils.ex", __DIR__)

# Ensure our application is started for tests
Application.ensure_all_started(:jido_ai)

if Code.loaded?(Mimic) do
  Mimic.copy(Req)
  # Mimic.copy(System)
  # Mimic.copy(Instructor)
  # Mimic.copy(Instructor.Adapters.Anthropic)
  # Mimic.copy(LangChain.ChatModels.ChatOpenAI)
  # Mimic.copy(LangChain.ChatModels.ChatAnthropic)
  # Mimic.copy(LangChain.Chains.LLMChain)
  # Mimic.copy(Finch)
  # Mimic.copy(OpenaiEx)
  # Mimic.copy(OpenaiEx.Chat.Completions)
  # Mimic.copy(OpenaiEx.Embeddings)
  # Mimic.copy(OpenaiEx.Images)
  # Mimic.copy(Dotenvy)
  # Mimic.copy(Jido.AI.Keyring)
  # Mimic.copy(Jido.Exec)
  # Mimic.copy(Jido.AI.Actions.Instructor)
  # Mimic.copy(Jido.AI.Actions.Langchain)
  # Mimic.copy(Jido.AI.Actions.OpenaiEx)
end
