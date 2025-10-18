defmodule Jido.AI.TestCleanup do
  @moduledoc """
  Centralized cleanup utilities for test suite to prevent memory leaks.

  This module provides helpers to clean up resources that can accumulate
  during test runs, including:
  - Conversation Manager state
  - Model Registry caches
  - Capability indexes
  - Session authentication data
  """

  alias Jido.AI.Model.Registry.Cache, as: RegistryCache
  alias Jido.AI.ReqLlmBridge.ConversationManager
  alias Jido.AI.ReqLlmBridge.SessionAuthentication

  @doc """
  Performs a complete cleanup of all test resources.

  This should be called in test setup or teardown to ensure a clean state.

  ## Examples

      setup do
        on_exit(fn -> TestCleanup.cleanup_all() end)
        :ok
      end
  """
  @spec cleanup_all() :: :ok
  def cleanup_all do
    cleanup_conversations()
    cleanup_caches()
    cleanup_sessions()
    :ok
  end

  @doc """
  Cleans up all conversations from ConversationManager.

  Removes all active conversations to free memory.
  """
  @spec cleanup_conversations() :: :ok
  def cleanup_conversations do
    try do
      ConversationManager.clear_all_conversations()
    rescue
      _ -> :ok
    end
  end

  @doc """
  Cleans up all caches including model registry cache.

  Clears all cached data to free memory.
  """
  @spec cleanup_caches() :: :ok
  def cleanup_caches do
    try do
      RegistryCache.clear()
    rescue
      _ -> :ok
    end
  end

  @doc """
  Cleans up session authentication data for the current process.

  Removes all session-specific authentication values.
  """
  @spec cleanup_sessions() :: :ok
  def cleanup_sessions do
    try do
      SessionAuthentication.clear_all()
    rescue
      _ -> :ok
    end
  end

  @doc """
  Returns a setup function that can be used with ExUnit.

  Use this in your test module's setup block:

  ## Examples

      setup do
        Jido.AI.TestCleanup.cleanup_all()
        :ok
      end

  Or use directly:

      setup do
        on_exit(fn -> Jido.AI.TestCleanup.cleanup_all() end)
        :ok
      end
  """
  @spec setup_helper(map()) :: :ok
  def setup_helper(_context) do
    cleanup_all()
    :ok
  end
end
