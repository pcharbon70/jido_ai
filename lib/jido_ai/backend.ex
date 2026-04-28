defmodule Jido.AI.Backend do
  # covers: package.jido_ai.explicit_policy_boundaries jido_ai.runtime_contracts.backend_normalization_boundary
  @moduledoc """
  Internal behaviour for backend-owned LLM execution.

  Backend implementations are responsible for translating transport-specific
  request, stream, and cancellation semantics behind a stable internal request,
  result, event, and capability contract.
  """

  alias Jido.AI.Backend.{Capabilities, Request, Result}

  @type stream_result :: {:ok, Enumerable.t()} | {:error, term()}
  @type generate_result :: {:ok, Result.t()} | {:error, term()}
  @type cancel_result :: :ok | {:ok, term()} | {:error, term()}

  @callback id() :: atom()
  @callback capabilities() :: Capabilities.t()
  @callback generate(Request.t()) :: generate_result()
  @callback stream(Request.t()) :: stream_result()
  @callback cancel(term(), keyword()) :: cancel_result()

  @doc """
  Validates that a backend can satisfy a request before transport execution begins.
  """
  @spec validate_request(module(), Request.t()) :: :ok | {:error, term()}
  def validate_request(backend, %Request{} = request) when is_atom(backend) do
    with true <- function_exported?(backend, :capabilities, 0),
         capabilities <- backend.capabilities() do
      Capabilities.validate_request(capabilities, request, backend: backend_id(backend))
    else
      false ->
        {:error, Jido.AI.Error.Backend.UnsupportedBackend.exception(backend: backend)}
    end
  end

  @doc """
  Returns true when the backend advertises support for the capability.
  """
  @spec supports?(module(), Capabilities.capability()) :: boolean()
  def supports?(backend, capability) when is_atom(backend) do
    function_exported?(backend, :capabilities, 0) and
      Capabilities.supports?(backend.capabilities(), capability)
  end

  defp backend_id(backend) do
    if function_exported?(backend, :id, 0) do
      backend.id()
    else
      backend
    end
  end
end
