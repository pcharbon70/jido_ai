defmodule Jido.AI.Error do
  # covers: jido_ai.security_and_errors.structured_error_taxonomy
  @moduledoc """
  Splode-based error handling for Jido.AI.

  Provides structured error types for AI operations including:
  - API errors (rate limits, authentication, transient failures)
  - Validation errors
  """

  use Splode,
    error_classes: [
      api: Jido.AI.Error.API,
      validation: Jido.AI.Error.Validation,
      backend: Jido.AI.Error.Backend
    ],
    unknown_error: Jido.AI.Error.Unknown
end

defmodule Jido.AI.Error.API do
  @moduledoc "API-level errors from LLM providers"

  use Splode.ErrorClass,
    class: :api
end

defmodule Jido.AI.Error.Validation do
  @moduledoc "Input/output validation errors"

  use Splode.ErrorClass,
    class: :validation
end

defmodule Jido.AI.Error.Backend do
  @moduledoc "Backend-selection and capability errors"

  use Splode.ErrorClass,
    class: :backend
end

defmodule Jido.AI.Error.Unknown do
  @moduledoc "Fallback error for unknown error types"

  use Splode.Error,
    fields: [:error],
    class: :unknown

  @impl true
  def message(%{error: error}) do
    "Unknown error: #{inspect(error)}"
  end
end

# ============================================================================
# API Error Types
# ============================================================================

defmodule Jido.AI.Error.API.RateLimit do
  @moduledoc "Rate limit exceeded error"

  use Splode.Error,
    fields: [:message, :retry_after],
    class: :api

  @impl true
  def message(%{message: message}) when is_binary(message), do: message

  def message(%{retry_after: seconds}) when is_integer(seconds),
    do: "Rate limit exceeded, retry after #{seconds} seconds"

  def message(_), do: "Rate limit exceeded"
end

defmodule Jido.AI.Error.API.Auth do
  @moduledoc "Authentication/authorization error"

  use Splode.Error,
    fields: [:message],
    class: :api

  @impl true
  def message(%{message: message}) when is_binary(message), do: message
  def message(_), do: "Authentication failed"
end

defmodule Jido.AI.Error.API.Request do
  @moduledoc """
  Transient request failure error.

  Covers timeout, network, and provider errors - all transient failures
  that may be retried.
  """

  use Splode.Error,
    fields: [:message, :kind, :status],
    class: :api

  @type kind :: :timeout | :network | :provider

  @impl true
  def message(%{message: message}) when is_binary(message), do: message
  def message(%{kind: :timeout}), do: "Request timed out"
  def message(%{kind: :network}), do: "Network error"
  def message(%{kind: :provider, status: status}) when is_integer(status), do: "Provider error (#{status})"
  def message(%{kind: :provider}), do: "Provider error"
  def message(_), do: "Request failed"
end

# ============================================================================
# Validation Error Types
# ============================================================================

defmodule Jido.AI.Error.Validation.Invalid do
  @moduledoc "Input validation error"

  use Splode.Error,
    fields: [:message, :field],
    class: :validation

  @impl true
  def message(%{message: message}) when is_binary(message), do: message
  def message(%{field: field}) when is_binary(field), do: "Invalid field: #{field}"
  def message(_), do: "Validation error"
end

# ============================================================================
# Backend Error Types
# ============================================================================

defmodule Jido.AI.Error.Backend.UnsupportedBackend do
  @moduledoc "Requested backend is not available or not supported"

  use Splode.Error,
    fields: [:backend, :supported_backends, :message],
    class: :backend

  @impl true
  def message(%{message: message}) when is_binary(message), do: message

  def message(%{backend: backend, supported_backends: supported})
      when not is_nil(backend) and is_list(supported) and supported != [] do
    "Unsupported backend #{inspect(backend)}. Supported backends: #{Enum.map_join(supported, ", ", &inspect/1)}"
  end

  def message(%{backend: backend}) when not is_nil(backend), do: "Unsupported backend #{inspect(backend)}"
  def message(_), do: "Unsupported backend"
end

defmodule Jido.AI.Error.Backend.UnsupportedCapability do
  @moduledoc "Requested backend cannot satisfy one of the required capabilities"

  use Splode.Error,
    fields: [:backend, :capability, :operation, :message],
    class: :backend

  @impl true
  def message(%{message: message}) when is_binary(message), do: message

  def message(%{backend: backend, capability: capability, operation: operation})
      when not is_nil(backend) and not is_nil(capability) and not is_nil(operation) do
    "Backend #{inspect(backend)} does not support #{inspect(capability)} for #{inspect(operation)} requests"
  end

  def message(%{capability: capability}) when not is_nil(capability),
    do: "Unsupported backend capability: #{inspect(capability)}"

  def message(_), do: "Unsupported backend capability"
end
