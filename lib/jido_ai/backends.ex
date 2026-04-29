defmodule Jido.AI.Backends do
  # covers: package.jido_ai.public_api_surface_compatibility jido_ai.core_runtime.additive_backend_selection jido_ai.tooling_and_configuration.explicit_configuration_defaults
  @moduledoc """
  Additive backend-selection helpers for Jido.AI.

  This module keeps backend choice explicit without changing the existing
  request-bearing public API surface. ReqLLM remains the default path, while
  alternate backend configuration is additive and explicit.
  """

  alias Jido.AI.Backend
  alias Jido.AI.Backend.Event
  alias Jido.AI.Backend.Request

  @default_backend :req_llm
  @reserved_backends %{
    req_llm: %{transport: :api, adapter: Jido.AI.Backends.ReqLLM},
    harness: %{
      transport: :exec,
      adapter: Jido.AI.Backends.Harness,
      provider: nil,
      request_defaults: %{},
      run_opts: []
    }
  }

  @type backend :: :req_llm | :harness | atom()
  @type backend_config :: %{optional(atom()) => term()}
  @type stream_event_handler :: (Event.t() -> any())

  @doc """
  Returns the configured default backend, falling back to `:req_llm`.
  """
  @spec default_backend() :: backend()
  def default_backend do
    case Application.get_env(:jido_ai, :llm_backend, @default_backend) do
      backend when is_atom(backend) -> backend
      _ -> @default_backend
    end
  end

  @doc """
  Returns the reserved backend config merged with additive app overrides.
  """
  @spec configured_backends() :: %{backend() => backend_config()}
  def configured_backends do
    configured =
      :jido_ai
      |> Application.get_env(:llm_backends, %{})
      |> normalize_backend_configs()

    Map.merge(@reserved_backends, configured, fn _backend, default_config, override_config ->
      Map.merge(default_config, override_config)
    end)
  end

  @doc """
  Returns the effective config for one backend.
  """
  @spec config_for(backend()) :: backend_config()
  def config_for(backend) when is_atom(backend) do
    Map.get(configured_backends(), backend, %{adapter: adapter_module(backend)})
  end

  @doc """
  Returns the adapter module for the resolved backend.
  """
  @spec adapter_for(backend()) :: module()
  def adapter_for(backend) when is_atom(backend) do
    config_for(backend)[:adapter] || adapter_module(backend)
  end

  @doc """
  Dispatches a normalized generation request through the resolved backend adapter.
  """
  @spec generate(Request.t()) :: Backend.generate_result()
  def generate(%Request{} = request) do
    request = ensure_request_backend(request)
    dispatch(adapter_for(request.backend), :generate, request)
  end

  @doc """
  Dispatches a normalized streaming request through the resolved backend adapter.
  """
  @spec stream(Request.t()) :: Backend.stream_result()
  def stream(%Request{} = request) do
    request = ensure_request_backend(request)
    dispatch(adapter_for(request.backend), :stream, request)
  end

  @doc """
  Runs a streaming request through the resolved backend while translating raw
  provider progress into backend-neutral events for the caller.
  """
  @spec run_stream(Request.t(), stream_event_handler()) ::
          {:ok, Jido.AI.Backend.Result.t()} | {:error, term()}
  def run_stream(%Request{} = request, on_event) when is_function(on_event, 1) do
    request = ensure_request_backend(request)
    dispatch_run_stream(adapter_for(request.backend), request, on_event)
  end

  @doc """
  Resolves the requested backend from request-scoped options or app config.
  """
  @spec request_backend(keyword() | map() | Request.t() | nil) :: backend()
  def request_backend(%Request{backend: backend}) when is_atom(backend) and not is_nil(backend), do: backend
  def request_backend(%Request{}), do: default_backend()
  def request_backend(opts) when is_list(opts), do: normalize_backend(Keyword.get(opts, :backend, default_backend()))

  def request_backend(opts) when is_map(opts) do
    opts
    |> Map.get(:backend, Map.get(opts, "backend", default_backend()))
    |> normalize_backend()
  end

  def request_backend(nil), do: default_backend()
  def request_backend(_), do: default_backend()

  @doc """
  Validates that the resolved backend is supported by the current call path.
  """
  @spec ensure_supported_backend(keyword() | map() | Request.t() | nil, [backend()]) ::
          {:ok, backend()} | {:error, term()}
  def ensure_supported_backend(opts_or_request, supported_backends \\ [:req_llm]) when is_list(supported_backends) do
    backend = request_backend(opts_or_request)
    supported_backends = Enum.uniq(supported_backends)

    if backend in supported_backends do
      {:ok, backend}
    else
      {:error,
       Jido.AI.Error.Backend.UnsupportedBackend.exception(
         backend: backend,
         supported_backends: supported_backends
       )}
    end
  end

  defp normalize_backend_configs(configs) when is_map(configs) do
    Enum.reduce(configs, %{}, fn
      {backend, config}, acc when is_atom(backend) and is_map(config) ->
        Map.put(acc, backend, config)

      {backend, config}, acc when is_binary(backend) and is_map(config) ->
        case reserved_backend_from_string(backend) do
          {:ok, backend_atom} -> Map.put(acc, backend_atom, config)
          :error -> acc
        end

      _, acc ->
        acc
    end)
  end

  defp normalize_backend_configs(_), do: %{}

  defp normalize_backend(backend) when is_atom(backend) and not is_nil(backend), do: backend

  defp normalize_backend(backend) when is_binary(backend) do
    case reserved_backend_from_string(backend) do
      {:ok, backend_atom} -> backend_atom
      :error -> default_backend()
    end
  end

  defp normalize_backend(_backend), do: default_backend()

  defp ensure_request_backend(%Request{} = request) do
    backend = request_backend(request)
    %{request | backend: backend}
  end

  defp dispatch(adapter, function_name, %Request{} = request) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, function_name, 1) do
      apply(adapter, function_name, [request])
    else
      {:error, Jido.AI.Error.Backend.UnsupportedBackend.exception(backend: request.backend)}
    end
  end

  defp dispatch_run_stream(adapter, %Request{} = request, on_event) when is_function(on_event, 1) do
    cond do
      not Code.ensure_loaded?(adapter) ->
        {:error, Jido.AI.Error.Backend.UnsupportedBackend.exception(backend: request.backend)}

      function_exported?(adapter, :run_stream, 2) ->
        apply(adapter, :run_stream, [request, on_event])

      true ->
        {:error,
         Jido.AI.Error.Backend.UnsupportedCapability.exception(
           backend: request.backend,
           capability: :streaming,
           operation: request.operation
         )}
    end
  end

  defp reserved_backend_from_string("req_llm"), do: {:ok, :req_llm}
  defp reserved_backend_from_string("harness"), do: {:ok, :harness}
  defp reserved_backend_from_string(_), do: :error

  defp adapter_module(:req_llm), do: Jido.AI.Backends.ReqLLM
  defp adapter_module(:harness), do: Jido.AI.Backends.Harness

  defp adapter_module(backend) when is_atom(backend) do
    backend
    |> Atom.to_string()
    |> Macro.camelize()
    |> then(&Module.concat([Jido, AI, Backends, &1]))
  end
end
