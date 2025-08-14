# Implementation Plan for Jido AI Refactor

This plan addresses critical issues in the Jido AI package including atom leaks, logger formatter bugs, performance optimizations, and code standardization. Each phase builds on the previous ones and can be implemented sequentially.

## Phase 0 - Safety Net Setup

**Prerequisites:**
- `mix test` must pass (baseline regression suite)
- `mix format` & `mix credo` must be clean
- Commit after each phase with tag `refactor/phase-<n>`

## Phase 1 - Config Tuning Knobs & Typespec Cleanup

**File:** `lib/jido_ai/config.ex`

### Step 1.1: Add Global Network Timeout Keys
**Location:** After `@config_http_client` (≈L55)
**Change:** Insert new config constants
```elixir
@config_receive_timeout :receive_timeout
@config_pool_timeout    :pool_timeout
@config_stream_inactivity_timeout :stream_inactivity_timeout
```

### Step 1.2: Fix HTTP Client Typespec
**Location:** Lines 184-187
**Find:**
```elixir
@spec get_http_client() :: Req | Req.Test
def get_http_client do
  Application.get_env(@env_app, @config_http_client, Req)
end
```
**Replace:**
```elixir
@spec get_http_client() :: module()
def get_http_client do
  Application.get_env(@env_app, @config_http_client, Req)
end
```

### Step 1.3: Add Timeout Helper Function
**Location:** Near bottom of file
**Add:**
```elixir
@spec get_timeout(atom(), integer()) :: integer()
def get_timeout(key, default) do
  Application.get_env(@env_app, key, default)
end
```

**Validation:**
- `mix dialyzer` shows no spec errors for `get_http_client/0`
- `Config.get_timeout/2` returns defaults when unset
- `mix test` still passes

## Phase 2 - Registry Error Consistency

**File:** `lib/jido_ai/provider/registry.ex`

### Step 2.1: Standardize Error Returns
**Location:** Lines 27-33 (get_provider/1 function)
**Find:**
```elixir
@spec get_provider(atom()) :: {:ok, module()} | {:error, String.t()}
def get_provider(provider_id) do
  case :persistent_term.get(@registry_key, %{}) do
    %{^provider_id => module} -> {:ok, module}
    _ -> {:error, "Unknown provider: #{provider_id}"}
  end
end
```
**Replace:**
```elixir
@spec get_provider(atom()) :: {:ok, module()} | {:error, Jido.AI.Error.Invalid.Parameter.t()}
def get_provider(provider_id) do
  case :persistent_term.get(@registry_key, %{}) do
    %{^provider_id => module} -> {:ok, module}
    _ ->
      {:error,
       Jido.AI.Error.Invalid.Parameter.exception(parameter: "provider #{provider_id}")}
  end
end
```

### Step 2.2: Add Reload Alias
**Location:** Just below `initialize/0` function
**Add:**
```elixir
@spec reload() :: :ok
def reload, do: initialize()
```

**Validation:**
- Create/update `test/provider_registry_test.exs` to verify unknown provider returns `{:error, %Error.Invalid.Parameter{}}`
- `mix test` passes

## Phase 3 - Keyring Atom Leak Fix & Performance

**File:** `lib/jido_ai/keyring.ex`

### Step 3.1: Binary Keys in ETS
**Location:** Lines 102-112 (init/1 function)
**Find the two `:ets.insert` calls and change to:**
```elixir
:ets.insert(env_table, {to_string(key), value})
# ... 
livebook_key = to_livebook_key(key)  # already returns binary
:ets.insert(env_table, {livebook_key, value})
```

### Step 3.2: Add Key Normalization Helper
**Location:** Near other private functions
**Add:**
```elixir
defp norm_key(k) when is_atom(k), do: Atom.to_string(k)
defp norm_key(k) when is_binary(k), do: k
```

### Step 3.3: Optimize get_env_value/3
**Location:** Lines 242-266 (entire get_env_value/3 function body)
**Replace entire function body:**
```elixir
env_table = env_table_name(server)

case :ets.whereis(env_table) do
  :undefined ->
    # Fallback for rare race conditions
    case GenServer.call(server, :get_env_table) do
      {:error, :env_table_not_found} -> default
      table -> do_env_lookup(table, key, default)
    end

  _table ->
    do_env_lookup(env_table, key, default)
end
```

### Step 3.4: Add Lookup Helpers
**Location:** After get_env_value/3 function
**Add:**
```elixir
def env_table_name(server \\ @default_name),
  do: generate_env_table_name(server)

defp do_env_lookup(table, key, default) do
  bin_key = norm_key(key)

  case :ets.lookup(table, bin_key) do
    [{^bin_key, v}] -> v
    [] ->
      lb = "lb_" <> bin_key
      case :ets.lookup(table, lb) do
        [{^lb, v}] -> v
        [] -> default
      end
  end
end
```

### Step 3.5: Relax GenServer Guards
**Location:** Multiple public functions
**Find and remove:** `and is_atom(server)` from guard clauses in:
- `get/3` (≈L206-208)
- `has_value?/2`
- `set_session_value/4`
- Any other functions with similar guards

**Validation:**
- Property test: inserting 1000 random env vars doesn't increase atom count (`:erlang.system_info(:atom_count)` stable)
- Benchmark: `Benchee.run(fn -> Keyring.get_env_value(:my_key) end)` shows ~2× speed-up vs main
- All existing unit tests pass
- Can call functions with PID instead of atom server name

## Phase 4 - Provider Base Cleanup

**File:** `lib/jido_ai/provider/base.ex`

### Step 4.1: Delegate API Key Lookup
**Location:** Lines 392-410 (put_api_key_from_env/2 function)
**Replace entire function:**
```elixir
defp put_api_key_from_env(opts, provider_info) do
  case Jido.AI.Config.get_api_key(provider_info.id) do
    nil -> opts
    key -> Keyword.put_new(opts, :api_key, key)
  end
end
```

### Step 4.2: Configurable Timeouts in generate_text_request/1
**Location:** Before `http_client.post/2` call (≈L238)
**Add:**
```elixir
recv_to = Keyword.get(opts, :receive_timeout,
            Config.get_timeout(:receive_timeout, 60_000))
pool_to = Keyword.get(opts, :pool_timeout,
            Config.get_timeout(:pool_timeout, 30_000))
```

**Then modify the http_client.post call:**
```elixir
http_client.post(url,
  json: Map.new(request_opts),
  auth: {:bearer, api_key},
  receive_timeout: recv_to,
  pool_timeout: pool_to
)
```

### Step 4.3: Configurable Timeouts in stream_text_request/1
**Location:** Inside Task.async/1 body (≈L298-310)
**Apply same timeout configuration as Step 4.2**

### Step 4.4: Stream Inactivity Timeout
**Location:** Hard-coded `after 15_000` in stream receive loop
**Replace:**
```elixir
inactivity_to = Keyword.get(opts, :stream_inactivity_timeout,
                  Config.get_timeout(:stream_inactivity_timeout, 15_000))
# ...
after inactivity_to ->
```

**Validation:**
- Unit test: call `Provider.Base.default_generate_text/4` with custom `receive_timeout: 5_000` and verify timeout reaches HTTP client
- Dialyzer passes with no spec errors

## Phase 5 - Model Construction Simplification

**File:** `lib/jido_ai/model.ex`

### Step 5.1: Replace get_provider_info/1 with Registry Lookup
**Location:** Lines 204-216
**Replace entire function:**
```elixir
defp get_provider_info(provider) do
  with {:ok, mod} <- Jido.AI.Provider.Registry.get_provider(provider) do
    {:ok, mod.api_url()}
  end
end
```

### Step 5.2: Safer Provider Parsing in from/1
**Location:** "provider:model" clause (≈L186-197)
**Replace:**
```elixir
[provider_str, model_name] ->
  with {:ok, provider} <- parse_provider(provider_str),
       {:ok, base_url} <- get_provider_info(provider) do
    from({provider, [model: model_name, base_url: base_url]})
  else
    {:error, reason} -> {:error, reason}
  end
```

### Step 5.3: Add Safe Provider Parser
**Location:** Near other private functions
**Add:**
```elixir
defp parse_provider(str) do
  case Jido.AI.Provider.Registry.list_providers()
       |> Enum.find(&(&1 |> Atom.to_string() == str)) do
    nil -> {:error, "Unknown provider: #{str}"}
    atom -> {:ok, atom}
  end
end
```

**Validation:**
- `Model.from("openrouter:anthropic/claude-3.5-sonnet")` works even if `:openrouter` atom wasn't previously loaded
- Remove any `String.to_existing_atom/1` calls - compile warnings should vanish
- `mix test` passes

## Phase 6 - Logger Sanitizer Correctness

**File:** `lib/jido_ai/keyring/filter.ex`

### Step 6.1: Fix Formatter Signature
**Location:** Line 51 (@spec format/4)
**Replace:**
```elixir
@spec format(Logger.level(), Logger.message(), Logger.Formatter.time(), Logger.metadata()) ::
        IO.chardata()
```

### Step 6.2: Fix Formatter Implementation  
**Location:** format/4 function head and body
**Replace:**
```elixir
def format(level, message, ts, metadata) do
  msg = sanitize_logger_message(message)
  md  = sanitize_data(metadata)
  ["[", to_string(level), "] ", msg, " ", inspect(md), "\n"]
end
```

### Step 6.3: Add Message Sanitization Helpers
**Location:** Near bottom of module
**Add:**
```elixir
defp sanitize_logger_message(fun) when is_function(fun, 0),
  do: sanitize_logger_message(fun.())
defp sanitize_logger_message(iodata),
  do: iodata |> IO.iodata_to_binary() |> sanitize_data()
```

### Step 6.4: Narrow Sensitive Key Patterns
**Location:** Lines 29-42 (sensitive_patterns/0 function)
**Replace with:**
```elixir
defp sensitive_patterns do
  [
    ~r/(^|[^a-z0-9])api[_-]?key($|[^a-z0-9])/i,
    ~r/(^|[^a-z0-9])(access|session)?[_-]?token($|[^a-z0-9])/i,
    ~r/(^|[^a-z0-9])bearer($|[^a-z0-9])/i,
    ~r/(^|[^a-z0-9])auth($|[^a-z0-9])/i,
    ~r/(^|[^a-z0-9])password|pass(word)?($|[^a-z0-9])/i,
    ~r/(^|[^a-z0-9])secret($|[^a-z0-9])/i,
    ~r/(^|[^a-z0-9])(private|encryption|signing|access|session)?[_-]?key($|[^a-z0-9])/i,
    ~r/(^|[^a-z0-9])cert($|[^a-z0-9])/i,
    ~r/(^|[^a-z0-9])pem($|[^a-z0-9])/i
  ]
end
```

### Step 6.5: Tighten Value Detection
**Location:** Lines 195-221 (looks_like_sensitive_value?/1 cond chain)
**Replace:**
```elixir
def looks_like_sensitive_value?(value) do
  cond do
    String.length(value) > 50 and String.contains?(value, ".") and
      Regex.match?(~r/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/, value) -> true
    Regex.match?(~r/^(gh[pousr]_|glpat-|gho_|ghu_|ghs_|ghr_)/, value) -> true
    Regex.match?(~r/^AKIA[0-9A-Z]{16}$/, value) -> true
    Regex.match?(~r/^sk-[A-Za-z0-9]{32,}$/, value) -> true
    true -> false
  end
end
```

### Step 6.6: Optional Translator Approach
**File:** `lib/jido_ai/application.ex`
**Location:** In start/2 function
**Add:**
```elixir
Logger.add_translator({Jido.AI.Keyring.Filter, :translate})
```

**File:** `lib/jido_ai/keyring/filter.ex`
**Add translate function:**
```elixir
def translate(_min, level, kind, {Logger, msg, ts, md}) do
  {:ok, {level, sanitize_logger_message(msg), ts, sanitize_data(md)}}
end
def translate(_min, _level, _kind, _event), do: :none
```

**Validation:**
- Unit test: log `%{password: "secret"}` and assert it contains `[REDACTED]` but `"monkey_id"` is NOT redacted
- Ensure no crashes when `Logger.info(fn -> "lazy" end)` is called
- Memory usage remains stable with high log volume

## Phase 7 - Final Verification & Cleanup

### Step 7.1: Quality Checks
- `mix dialyzer` - no errors
- `mix credo --strict` - all green  
- `mix docs` - builds successfully

### Step 7.2: Soak Testing
- Run stress test: 10,000 random env vars + 100,000 log lines
- Verify memory and atom count remain stable
- Monitor for any performance regressions

### Step 7.3: Release Preparation
- Tag release `vX.Y.Z`
- Update CHANGELOG.md with improvements
- Verify all tests pass in CI environment

## Success Criteria

After completing all phases:

1. **No atom leaks:** Environment variable processing doesn't create unbounded atoms
2. **Correct logger handling:** Formatter signature matches Logger expectations and handles all message types
3. **Improved performance:** Direct ETS access eliminates unnecessary GenServer calls
4. **Better security:** Sanitization is more precise with fewer false positives
5. **Consistent errors:** All modules use structured error types instead of strings
6. **Configurable timeouts:** Network operations can be tuned via configuration

## Dependencies Between Phases

- Phase 1 must complete before Phase 4 (Provider Base needs Config.get_timeout/2)
- Phase 2 must complete before Phase 5 (Model needs standardized Registry errors)
- Phase 3 can run independently but affects performance testing in Phase 7
- Phase 6 can run independently
- Phase 7 validates all previous changes

Each phase maintains backward compatibility and keeps the codebase in a compilable, test-passing state.
