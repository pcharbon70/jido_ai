defmodule Jido.AI.TestSupport.ProviderCase do
  @moduledoc """
  ExUnit case template for testing AI providers.

  Provides common setup and helper macros for testing provider implementations
  with HTTP mocking via Req.Test.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Jido.AI.TestSupport.ProviderCase

      alias Jido.AI.Model
      alias Jido.AI.TestSupport.Fixtures
    end
  end

  setup _tags do
    # Set up HTTP client with test plug
    Application.put_env(:jido_ai, :http_client, Req)
    Application.put_env(:jido_ai, :http_options, plug: {Req.Test, :provider_case})

    # Ensure clean test environment
    on_exit(fn ->
      try do
        Req.Test.verify!(:provider_case)
      rescue
        _ -> :ok
      end
    end)

    :ok
  end

  @doc """
  Sets up HTTP success response with given body.
  """
  defmacro with_http_success(body \\ quote(do: Fixtures.success_body()), do: block) do
    quote do
      Req.Test.stub(:provider_case, &Req.Test.json(&1, unquote(body)))
      unquote(block)
    end
  end

  @doc """
  Sets up HTTP error response with given status and body.
  """
  defmacro with_http_error(status, body \\ %{}, do: block) do
    quote do
      Req.Test.stub(:provider_case, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(unquote(status), Jason.encode!(unquote(body)))
      end)

      unquote(block)
    end
  end

  @doc """
  Sets up Server-Sent Events response with given event chunks.
  """
  defmacro with_sse_events(events, do: block) do
    quote do
      Req.Test.stub(:provider_case, fn conn ->
        conn =
          Enum.reduce(unquote(events), conn, fn event, c ->
            chunk_data = Jason.encode!(event)
            Req.Test.chunk(c, "data: #{chunk_data}\n\n")
          end)

        Req.Test.chunk(conn, "data: [DONE]\n\n")
      end)

      unquote(block)
    end
  end

  @doc """
  Sets up streaming response that immediately closes connection.
  """
  defmacro with_stream_error(do: block) do
    quote do
      Req.Test.stub(:provider_case, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{"error" => %{"message" => "Connection closed"}}))
      end)

      unquote(block)
    end
  end
end
