defmodule Jido.AI.Error do
  @moduledoc """
  Error handling system for Jido.AI using Splode.
  """

  use Splode,
    error_classes: [
      invalid: Jido.AI.Error.Invalid,
      api: Jido.AI.Error.API,
      unknown: Jido.AI.Error.Unknown
    ],
    unknown_error: Jido.AI.Error.Unknown.Unknown

  defmodule Invalid do
    use Splode.ErrorClass, class: :invalid
  end

  defmodule API do
    use Splode.ErrorClass, class: :api
  end

  defmodule Unknown do
    use Splode.ErrorClass, class: :unknown
  end

  defmodule Invalid.Parameter do
    use Splode.Error, fields: [:parameter], class: :invalid

    def message(%{parameter: parameter}) do
      "Invalid parameter: #{parameter}"
    end
  end

  defmodule API.Request do
    use Splode.Error, fields: [:reason], class: :api

    def message(%{reason: reason}) do
      "API request failed: #{reason}"
    end
  end

  defmodule Unknown.Unknown do
    use Splode.Error, fields: [:error], class: :unknown

    def message(%{error: error}) do
      "Unknown error: #{inspect(error)}"
    end
  end
end
