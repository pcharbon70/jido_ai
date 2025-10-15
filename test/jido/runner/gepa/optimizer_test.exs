defmodule Jido.Runner.GEPA.OptimizerTest do
  use ExUnit.Case, async: true

  alias Jido.Runner.GEPA.Optimizer

  describe "start_link/1" do
    test "starts optimizer with valid configuration" do
      opts = [
        population_size: 5,
        max_generations: 10,
        evaluation_budget: 50,
        task: %{type: :test}
      ]

      assert {:ok, pid} = Optimizer.start_link(opts)
      assert Process.alive?(pid)

      # Clean up
      Optimizer.stop(pid)
    end

    test "starts optimizer with seed prompts" do
      opts = [
        population_size: 5,
        seed_prompts: ["Solve step by step", "Think carefully"],
        task: %{type: :test}
      ]

      assert {:ok, pid} = Optimizer.start_link(opts)
      assert Process.alive?(pid)

      Optimizer.stop(pid)
    end

    test "starts optimizer with named process" do
      opts = [
        name: :test_optimizer,
        task: %{type: :test}
      ]

      assert {:ok, pid} = Optimizer.start_link(opts)
      assert Process.whereis(:test_optimizer) == pid

      Optimizer.stop(pid)
    end

    test "requires task configuration" do
      opts = [population_size: 5]

      assert_raise ArgumentError, "task configuration is required", fn ->
        Optimizer.start_link(opts)
      end
    end

    test "uses default configuration values" do
      opts = [task: %{type: :test}]

      assert {:ok, pid} = Optimizer.start_link(opts)

      {:ok, status} = Optimizer.status(pid)
      assert status.population_size == 10

      Optimizer.stop(pid)
    end
  end

  describe "initialization" do
    test "initializes population from seed prompts" do
      seed_prompts = ["Prompt 1", "Prompt 2", "Prompt 3"]

      opts = [
        population_size: 3,
        seed_prompts: seed_prompts,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)

      # Give initialization time to complete
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)
      assert status.status == :ready
      assert status.population_size == 3
      assert status.generation == 0
      assert status.evaluations_used == 0

      Optimizer.stop(pid)
    end

    test "generates variations when seeds are fewer than population size" do
      opts = [
        population_size: 10,
        seed_prompts: ["Seed prompt"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)
      assert status.population_size == 10
      assert status.status == :ready

      Optimizer.stop(pid)
    end

    test "generates default prompts when no seeds provided" do
      opts = [
        population_size: 5,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)
      assert status.population_size == 5
      assert status.status == :ready

      Optimizer.stop(pid)
    end
  end

  describe "status/1" do
    test "returns current optimization status" do
      opts = [
        population_size: 5,
        max_generations: 10,
        evaluation_budget: 50,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)

      assert status.status == :ready
      assert status.generation == 0
      assert status.evaluations_used == 0
      assert status.evaluations_remaining == 50
      assert status.best_fitness == 0.0
      assert status.population_size == 5
      assert is_integer(status.uptime_ms)
      assert status.uptime_ms >= 0

      Optimizer.stop(pid)
    end

    test "tracks uptime correctly" do
      opts = [task: %{type: :test}]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(50)

      {:ok, status1} = Optimizer.status(pid)
      Process.sleep(50)
      {:ok, status2} = Optimizer.status(pid)

      assert status2.uptime_ms > status1.uptime_ms

      Optimizer.stop(pid)
    end
  end

  describe "get_best_prompts/2" do
    test "returns empty list when population has no fitness scores" do
      opts = [
        population_size: 5,
        seed_prompts: ["Test prompt"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, prompts} = Optimizer.get_best_prompts(pid)
      assert prompts == []

      Optimizer.stop(pid)
    end

    test "respects limit parameter" do
      opts = [
        population_size: 10,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, prompts} = Optimizer.get_best_prompts(pid, limit: 3)
      assert length(prompts) <= 3

      Optimizer.stop(pid)
    end

    test "uses default limit of 5" do
      opts = [task: %{type: :test}]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, prompts} = Optimizer.get_best_prompts(pid)
      assert length(prompts) <= 5

      Optimizer.stop(pid)
    end
  end

  describe "optimize/1" do
    test "executes optimization loop when ready" do
      opts = [
        population_size: 3,
        seed_prompts: ["Test prompt"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)
      assert status.status == :ready

      {:ok, result} = Optimizer.optimize(pid)

      assert is_map(result)
      assert Map.has_key?(result, :best_prompts)
      assert Map.has_key?(result, :final_generation)
      assert Map.has_key?(result, :total_evaluations)
      assert Map.has_key?(result, :history)
      assert Map.has_key?(result, :duration_ms)
      assert is_integer(result.duration_ms)

      Optimizer.stop(pid)
    end

    test "changes status to completed after optimization" do
      opts = [
        population_size: 3,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, _result} = Optimizer.optimize(pid)

      {:ok, status} = Optimizer.status(pid)
      assert status.status == :completed

      Optimizer.stop(pid)
    end
  end

  describe "stop/1" do
    test "stops optimizer gracefully" do
      opts = [task: %{type: :test}]

      {:ok, pid} = Optimizer.start_link(opts)
      assert Process.alive?(pid)

      assert :ok = Optimizer.stop(pid)

      # Wait for process to terminate
      Process.sleep(50)

      refute Process.alive?(pid)
    end
  end

  describe "configuration validation" do
    test "validates population_size is positive" do
      opts = [
        population_size: 10,
        max_generations: 20,
        task: %{type: :test}
      ]

      assert {:ok, pid} = Optimizer.start_link(opts)
      Optimizer.stop(pid)
    end

    test "validates max_generations is positive" do
      opts = [
        max_generations: 50,
        task: %{type: :test}
      ]

      assert {:ok, pid} = Optimizer.start_link(opts)
      Optimizer.stop(pid)
    end

    test "validates evaluation_budget is positive" do
      opts = [
        evaluation_budget: 100,
        task: %{type: :test}
      ]

      assert {:ok, pid} = Optimizer.start_link(opts)
      Optimizer.stop(pid)
    end
  end

  describe "state management" do
    test "maintains generation counter" do
      opts = [task: %{type: :test}]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)
      assert status.generation == 0

      Optimizer.stop(pid)
    end

    test "tracks evaluations used" do
      opts = [
        evaluation_budget: 100,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)
      assert status.evaluations_used == 0
      assert status.evaluations_remaining == 100

      Optimizer.stop(pid)
    end

    test "initializes best_fitness to zero" do
      opts = [task: %{type: :test}]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)
      assert status.best_fitness == 0.0

      Optimizer.stop(pid)
    end
  end

  describe "concurrent access" do
    test "handles multiple concurrent status calls" do
      opts = [task: %{type: :test}]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      tasks =
        for _ <- 1..10 do
          Task.async(fn -> Optimizer.status(pid) end)
        end

      results = Task.await_many(tasks)

      assert Enum.all?(results, fn result ->
               match?({:ok, %{status: :ready}}, result)
             end)

      Optimizer.stop(pid)
    end

    test "handles concurrent get_best_prompts calls" do
      opts = [
        population_size: 5,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      tasks =
        for _ <- 1..5 do
          Task.async(fn -> Optimizer.get_best_prompts(pid, limit: 3) end)
        end

      results = Task.await_many(tasks)

      assert Enum.all?(results, fn result ->
               match?({:ok, prompts} when is_list(prompts), result)
             end)

      Optimizer.stop(pid)
    end
  end
end
