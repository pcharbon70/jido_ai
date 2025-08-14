defmodule Mix.Tasks.Jido.Ai.ModelSync do
  @moduledoc """
  Simplified model synchronization task.

  This task fetches model data from models.dev API (which now includes cost data)
  and saves provider JSON files to the /priv directory.

  ## Usage

      # Sync models from models.dev
      mix jido.ai.model_sync
      
      # Verbose output
      mix jido.ai.model_sync --verbose

  ## Output Structure

      priv/models_dev/providers/
      ├── anthropic.json         # Anthropic models with cost data
      ├── openai.json            # OpenAI models with cost data
      ├── google.json            # Google models with cost data
      └── ...                    # All other providers
  """

  use Mix.Task
  require Logger

  @shortdoc "Synchronize model data from models.dev API"

  # API endpoint
  @models_dev_api "https://models.dev/api.json"

  # Directory structure
  @providers_dir "priv/models_dev/providers"

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:jido_ai)

    {opts, _, _} =
      OptionParser.parse(args,
        switches: [
          verbose: :boolean
        ]
      )

    verbose? = Keyword.get(opts, :verbose, false)

    if verbose?, do: IO.puts("🚀 Starting model synchronization...")

    case execute_sync(verbose?) do
      :ok ->
        IO.puts("✅ Model synchronization completed successfully")

      {:error, reason} ->
        IO.puts("❌ Synchronization failed: #{reason}")
        System.halt(1)
    end
  end

  @doc """
  Execute the synchronization process.
  """
  def execute_sync(verbose? \\ false) do
    File.mkdir_p!(@providers_dir)

    with {:ok, models_data} <- fetch_models_dev_data(verbose?),
         :ok <- save_provider_files(models_data, verbose?) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_models_dev_data(verbose?) do
    if verbose?, do: IO.puts("📡 Fetching models.dev catalog...")

    case Req.get(@models_dev_api) do
      {:ok, %{status: 200, body: data}} ->
        if verbose? do
          provider_count = map_size(data)
          model_count = count_total_models(data)

          IO.puts(
            "✅ Downloaded models.dev data: #{provider_count} providers, #{model_count} models"
          )
        end

        {:ok, data}

      {:ok, %{status: status}} ->
        {:error, "models.dev API returned status #{status}"}

      {:error, reason} ->
        {:error, "Failed to fetch models.dev data: #{inspect(reason)}"}
    end
  end

  defp save_provider_files(models_data, verbose?) do
    models_data
    |> Enum.each(fn {provider_id, provider_data} ->
      models = process_provider_models(provider_data["models"] || %{}, provider_id)

      if length(models) > 0 do
        provider_file = Path.join(@providers_dir, "#{provider_id}.json")

        provider_json = %{
          "provider" => %{
            "id" => provider_id,
            "name" => format_provider_name(provider_id),
            "model_count" => length(models)
          },
          "models" => models
        }

        File.write!(provider_file, Jason.encode!(provider_json, pretty: true))

        if verbose? do
          IO.puts("  💾 Saved #{length(models)} models for #{provider_id}")
        end
      end
    end)

    :ok
  end

  defp process_provider_models(models_map, provider_id) do
    models_map
    |> Enum.map(fn {_model_id, model_data} ->
      Map.merge(model_data, %{
        "provider" => provider_id,
        "provider_model_id" => model_data["id"]
      })
    end)
  end

  defp count_total_models(providers_data) do
    providers_data
    |> Enum.map(fn {_, provider} -> map_size(provider["models"] || %{}) end)
    |> Enum.sum()
  end

  defp format_provider_name(provider_id) do
    provider_id
    |> String.split(["-", "_"])
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
