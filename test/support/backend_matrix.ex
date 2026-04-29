defmodule Jido.AI.TestSupport.BackendMatrix do
  # covers: jido_ai.examples_and_quality.quality_checkpoint_helpers
  @moduledoc false

  @tracked_jido_ai_keys [:llm_backend, :llm_backends, :model_aliases, :llm_defaults]

  def snapshot_jido_ai_env(keys \\ @tracked_jido_ai_keys) when is_list(keys) do
    Map.new(keys, fn key -> {key, Application.get_env(:jido_ai, key)} end)
  end

  def restore_jido_ai_env(snapshot) when is_map(snapshot) do
    Enum.each(snapshot, fn {key, value} ->
      restore_env(:jido_ai, key, value)
    end)

    :ok
  end

  def harness_backend_config(overrides \\ %{}) when is_map(overrides) do
    Map.merge(
      %{
        transport: :exec,
        provider: :codex,
        request_defaults: %{},
        run_opts: []
      },
      overrides
    )
  end

  defp restore_env(_app, key, nil), do: Application.delete_env(:jido_ai, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
