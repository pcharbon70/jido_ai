defmodule Jido.AI.Test.FakeProvider do
  @moduledoc """
  Fake provider for testing the AI interface.

  This provider can be used across test suites to simulate AI provider behavior
  without making real API calls.
  """

  @behaviour Jido.AI.Provider.Base

  alias Jido.AI.{Model, Provider}

  @impl true
  def provider_info do
    %Provider{
      id: :fake,
      name: "Fake Provider",
      base_url: "https://fake.test/v1",
      env: [:fake_api_key],
      doc: "Test provider for unit tests",
      models: %{
        "fake-model" => %Model{
          provider: :fake,
          model: "fake-model",
          id: "fake-model",
          name: "Fake Model",
          attachment: false,
          reasoning: false,
          supports_temperature: true,
          tool_call: false,
          release_date: "2024-01",
          last_updated: "2024-01",
          modalities: %{input: [:text], output: [:text]},
          open_weights: false,
          limit: %{context: 128_000, output: 4096}
        }
      }
    }
  end

  @impl true
  def api_url, do: "https://fake.test/v1"

  @impl true
  def generate_text(%Model{} = model, prompt, opts) do
    # Use the base implementation's option merging for testing
    merged_opts = Jido.AI.Provider.Base.merge_model_options(__MODULE__, model, opts)
    {:ok, "#{model.model}:#{prompt}:#{inspect(merged_opts)}"}
  end

  @impl true
  def stream_text(%Model{} = _model, _prompt, _opts) do
    {:ok, Stream.iterate(1, &(&1 + 1)) |> Stream.take(3) |> Stream.map(&"chunk_#{&1}")}
  end
end
