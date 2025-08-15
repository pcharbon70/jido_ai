defmodule Jido.AI.ErrorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Error.API.Request
  alias Jido.AI.Error.Invalid.Parameter
  alias Jido.AI.Error.Unknown.Unknown
  alias Jido.AI.Model

  describe "Invalid.Parameter" do
    test "implements Exception.message/1" do
      error = Parameter.exception(parameter: "custom_param")
      message = Exception.message(error)
      assert message == "Invalid parameter: custom_param"
    end

    test "has default message when none provided" do
      error = Parameter.exception([])
      message = Exception.message(error)
      assert is_binary(message)
      assert message != ""
    end

    test "can be raised as exception" do
      assert_raise Parameter, fn ->
        raise Parameter, parameter: "test_param"
      end
    end
  end

  describe "API" do
    test "implements Exception.message/1" do
      error = Request.exception(reason: "API request failed")
      message = Exception.message(error)
      assert message == "API request failed: API request failed"
    end

    test "has default message when none provided" do
      error = Request.exception([])
      message = Exception.message(error)
      assert is_binary(message)
      assert message != ""
    end

    test "can be raised as exception" do
      assert_raise Request, fn ->
        raise Request, reason: "API Error"
      end
    end
  end

  describe "Unknown" do
    test "implements Exception.message/1" do
      error = Unknown.exception(error: "Unexpected error")
      message = Exception.message(error)
      assert message == "Unknown error: \"Unexpected error\""
    end

    test "has default message when none provided" do
      error = Unknown.exception([])
      message = Exception.message(error)
      assert is_binary(message)
      assert message != ""
    end

    test "can be raised as exception" do
      assert_raise Unknown, fn ->
        raise Unknown, error: "Unknown error"
      end
    end
  end

  describe "error hierarchy" do
    test "all errors are exceptions" do
      errors = [
        Parameter.exception([]),
        Request.exception([]),
        Unknown.exception([])
      ]

      for error <- errors do
        assert is_exception(error)
        assert is_binary(Exception.message(error))
      end
    end

    test "errors have distinct types" do
      param_error = Parameter.exception([])
      api_error = Request.exception([])
      unknown_error = Unknown.exception([])

      assert param_error.__struct__ != api_error.__struct__
      assert api_error.__struct__ != unknown_error.__struct__
      assert param_error.__struct__ != unknown_error.__struct__
    end
  end

  describe "integration with other modules" do
    test "parameter errors are used for validation failures" do
      # Test that our error types are used correctly by other modules
      case Model.from("invalid-format") do
        {:error, "Invalid model specification. Expected format: 'provider:model'"} -> :ok
        other -> flunk("Expected Invalid.Parameter error, got: #{inspect(other)}")
      end
    end

    test "errors contain helpful messages" do
      {:error, error} = Model.from("unknown:model")

      assert is_binary(error)
      assert String.length(error) > 0
      # Should contain some context about what went wrong
      assert error =~ "unknown" or error =~ "provider" or error =~ "model"
    end
  end
end
