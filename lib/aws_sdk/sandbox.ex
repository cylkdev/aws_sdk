if Code.ensure_loaded?(SandboxRegistry) do
  defmodule AwsSDK.Sandbox do
    @moduledoc """
    Process-scoped registry of stub functions.

    Stores functions against the calling process, keyed by the function they
    stand in for and a lookup key, then applies them on demand. It holds no
    domain knowledge: a stub is any function, and whatever it returns is
    passed back untouched.

    ## Observable behaviour

      * `register/4` associates stubs with the calling process.
      * `apply/5` resolves one stub and calls it, returning what the stub
        returns and raising when it cannot resolve one.
      * Registrations accumulate. Registering a second function leaves the
        first in place; registering the same `{function, key}` twice keeps
        the later stub.
      * Stubs are scoped to the process that registered them, and resolve
        from its descendants too — anything carrying `$callers` or
        `$ancestors`, such as a `Task` — so code under test may spawn freely.
        An unrelated process resolves nothing.
      * `disable/2` flags the calling process and `disabled?/2` reports that
        flag. Neither affects what `apply/5` resolves — a caller checks
        `disabled?/2` itself before deciding to consult the sandbox at all.

    ## Usage

    A module backed by this registry holds its registry name and writes one
    pair of functions per stubbed call:

        defmodule MyApp.Sandbox do
          @registry :my_sandbox

          alias AwsSDK.Sandbox

          def fetch_record_response(id, opts) do
            binding = [id: id, opts: opts]

            Sandbox.apply(@registry, __MODULE__, :fetch_record, id, binding)
          end

          def set_fetch_record_responses(entries) do
            Sandbox.register(@registry, __MODULE__, :fetch_record, entries)
          end
        end

    ## Convention

    The messages raised by `apply/5` name the registration function
    `set_<function>_responses/1`. A module that names its setter otherwise
    still works; only the suggestion in the message is wrong.
    """

    @state "state"
    @disabled "disabled"
    @sleep 10

    # A registry of duplicate keys, so every test process holds its own entry
    # under the one context and `SandboxRegistry.lookup/2` picks the entry
    # belonging to the caller or one of its ancestors. A unique registry lets
    # one process own the context at a time, and every other process spins in
    # `SandboxRegistry.register/4`'s retry until that one exits — which is a
    # busy wait that grows with the size of the suite, not isolation.
    @keys :duplicate

    @typedoc """
    Selects which registered stub a call resolves to.

    A binary names one call. `:*` applies to every call of that function.
    """
    @type key :: String.t() | :*

    @doc """
    Starts the registry `registry` under the calling process.

    Call it once per registry, before any process registers stubs — typically
    from `test/test_helper.exs`. Returns `{:ok, pid}`, or
    `{:error, {:already_started, pid}}` if that name is already taken.

    Every other function in this module raises if its registry was never
    started.
    """
    @spec start_link(atom) :: {:ok, pid} | {:error, term}
    def start_link(registry), do: Registry.start_link(keys: @keys, name: registry)

    @doc """
    Flags the calling process as opted out of the sandbox.

    The flag is per-process and is stored separately from stubs, so it
    neither removes registrations nor changes what `apply/5` resolves.
    Callers read it through `disabled?/2` and decide for themselves whether
    to consult the sandbox.

    Returns `:ok`. Raises if `registry` was never started, naming `module` in
    the message.
    """
    @spec disable(atom, module) :: :ok
    def disable(registry, module) do
      with {:error, :registry_not_started} <- put_state(registry, @disabled, %{}) do
        raise_not_started!(module)
      end
    end

    @doc """
    Reports whether the calling process was flagged by `disable/2`.

    `false` for a process that never called it. Raises if `registry` was
    never started, naming `module` in the message.
    """
    @spec disabled?(atom, module) :: boolean
    def disabled?(registry, module) do
      case SandboxRegistry.lookup(registry, @disabled) do
        {:ok, _} -> true
        {:error, :registry_not_started} -> raise_not_started!(module)
        {:error, :pid_not_registered} -> false
      end
    end

    @doc """
    Resolves the stub registered for `function` and applies it.

    ## Arguments

      * `registry` — the registry to read. Must already be started.
      * `module` — diagnostic only. It never participates in lookup; it names
        the module in raised messages.
      * `function` — half of the lookup key. A stub registered under a
        different `function` never matches.
      * `key` — the other half. A binary selects one call, so one process can
        register a different stub per subject; `:*` applies to every call of
        `function`. `nil` is not valid and fails the guard.
      * `binding` — a keyword list of names to values. The names appear in
        raised messages as `fn` shapes; the values are applied to the stub, in
        the order given. Write this list out by hand: `Kernel.binding/0`
        returns variables sorted alphabetically rather than in declaration
        order, which would apply the values to the wrong parameters.

    ## Lookup

    By `{function, key}`, in three ordered steps:

      1. **exact** — a binary key equal to `key`
      2. **pattern** — a `Regex` key registered for the same `function` whose
         pattern matches `key`. Skipped unless `key` is a binary, so
         `Regex.match?/2` is never handed an atom.
      3. **wildcard** — a stub registered under `:*`

    If several patterns match, which one wins is unspecified — register
    non-overlapping patterns. Stubs are held in a map, and map iteration is
    neither insertion nor sorted order.

    ## Return value

    Whatever the stub returns, unaltered — this module never inspects or wraps
    it.

    The stub is applied at its own arity, so the registering process writes
    only the parameters it cares about. Arity `0` is called with no arguments;
    any arity up to `length(binding)` receives that many leading values.

    ## Raises

      * `registry` was never started — the message points at `test_helper.exs`
      * the calling process registered no stubs at all
      * stubs exist for this process but none match `{function, key}` — the
        message lists what was registered
      * a registered value is not a function
      * a registered function's arity exceeds `length(binding)`

    ## Examples

        AwsSDK.Sandbox.register(:my_sandbox, MyApp.Sandbox, :fetch_record, [
          {"alpha", fn -> {:ok, %{id: "alpha"}} end}
        ])

        AwsSDK.Sandbox.apply(:my_sandbox, MyApp.Sandbox, :fetch_record, "alpha",
          id: "alpha",
          opts: []
        )
        #=> {:ok, %{id: "alpha"}}

    An unmatched key raises rather than falling back to another stub:

        AwsSDK.Sandbox.apply(:my_sandbox, MyApp.Sandbox, :fetch_record, "beta", id: "beta", opts: [])
        #=> ** (RuntimeError) Function not found.

    A stub of higher arity receives the binding's values in order:

        AwsSDK.Sandbox.register(:my_sandbox, MyApp.Sandbox, :fetch_record, [
          {~r/^live-/, fn id, opts -> {:ok, %{id: id, limit: opts[:limit]}} end}
        ])

        AwsSDK.Sandbox.apply(:my_sandbox, MyApp.Sandbox, :fetch_record, "live-1",
          id: "live-1",
          opts: [limit: 5]
        )
        #=> {:ok, %{id: "live-1", limit: 5}}

    A call with nothing to select on passes `:*`:

        AwsSDK.Sandbox.register(:my_sandbox, MyApp.Sandbox, :list_records, [
          fn -> {:ok, []} end
        ])

        AwsSDK.Sandbox.apply(:my_sandbox, MyApp.Sandbox, :list_records, :*, opts: [])
        #=> {:ok, []}
    """
    @spec apply(atom, module, atom, key, keyword) :: term
    def apply(registry, module, function, key, binding)
        when is_binary(key) or key === :* do
      names = Keyword.keys(binding)
      args = Keyword.values(binding)
      examples = examples(names)
      fun = fetch!(registry, module, function, key, examples)
      arity = :erlang.fun_info(fun)[:arity]

      case arity do
        0 -> fun.()
        n when n <= length(args) -> Kernel.apply(fun, Enum.take(args, n))
        _ -> raise_unsupported_arity(fun, examples)
      end
    end

    @doc """
    Registers stub functions for `function` against the calling process.

    Each entry is a `{key, fun}` tuple, or a bare `fun` — shorthand for
    `{:*, fun}`.

    `key` is an exact binary compared for equality against the key passed to
    `apply/5`, a `Regex` matched against it, or `:*` to match every call.

    Registrations accumulate: registering a second `function` leaves the first
    in place, and registering the same `{function, key}` twice keeps the later
    stub. They are scoped to the calling process and resolve from its
    descendants as well — see the module documentation.

    Returns `:ok` after a short sleep, so the registration is visible before
    the caller proceeds. Raises if `registry` was never started, naming
    `module` in the message.

    ## Examples

    One stub per subject:

        AwsSDK.Sandbox.register(:my_sandbox, MyApp.Sandbox, :fetch_record, [
          {"alpha", fn -> {:ok, %{id: "alpha"}} end},
          {"beta", fn -> {:error, :not_found} end}
        ])

    A pattern covering a family of keys, receiving the key it matched:

        AwsSDK.Sandbox.register(:my_sandbox, MyApp.Sandbox, :fetch_record, [
          {~r/^live-/, fn id -> {:ok, %{id: id}} end}
        ])

    Every call, whatever the key — the two forms are equivalent:

        AwsSDK.Sandbox.register(:my_sandbox, MyApp.Sandbox, :list_records, [
          {:*, fn -> {:ok, []} end}
        ])

        AwsSDK.Sandbox.register(:my_sandbox, MyApp.Sandbox, :list_records, [
          fn -> {:ok, []} end
        ])
    """
    @spec register(atom, module, atom, [{key | Regex.t(), function} | function]) :: :ok
    def register(registry, module, function, entries) do
      :ok =
        entries
        |> Enum.map(fn
          {_key, _fun} = entry -> entry
          fun when is_function(fun) -> {:*, fun}
        end)
        |> Map.new(fn {key, fun} -> {{function, key}, fun} end)
        |> then(&put_state(registry, @state, &1))
        |> then(fn
          :ok -> :ok
          {:error, :registry_not_started} -> raise_not_started!(module)
        end)

      :ok = Process.sleep(@sleep)
    end

    # Writes `state` into the calling process's entry for `context`, merged
    # with whatever it already holds.
    #
    # A duplicate-key registry lets one process register a key more than once,
    # and `SandboxRegistry.lookup/2` reads the first entry it finds for that
    # pid — so a second registration would shadow the first rather than add to
    # it. Registering stubs for two functions in one test is ordinary, so the
    # entry is read, merged and rewritten, leaving exactly one per process.
    defp put_state(registry, context, state) do
      case Process.whereis(registry) do
        nil ->
          {:error, :registry_not_started}

        _pid_or_port ->
          merged =
            case SandboxRegistry.lookup(registry, context) do
              {:ok, existing} when is_map(existing) -> Map.merge(existing, state)
              _unregistered -> state
            end

          Registry.unregister(registry, context)
          Registry.register(registry, context, merged)

          :ok
      end
    end

    # -------------------------------------------------------------------------
    # Lookup
    # -------------------------------------------------------------------------

    defp fetch!(registry, module, function, key, examples) do
      case SandboxRegistry.lookup(registry, @state) do
        {:ok, state} ->
          fetch_stub!(state, module, function, key, examples)

        {:error, :pid_not_registered} ->
          raise """
          No functions have been registered for #{inspect(self())}.

          Function: #{inspect(function)}
          Key: #{inspect(key)}

          Add one of the following patterns to your test setup:

          #{format_example(module, function, examples)}

          Replace `_response` with the value you want the sandbox to return.
          """

        {:error, :registry_not_started} ->
          raise_not_started!(module)
      end
    end

    defp fetch_stub!(state, module, function, key, examples) do
      exact = Map.get(state, {function, key})
      pattern = if is_binary(key), do: match_pattern(state, function, key)
      wildcard = Map.get(state, {function, :*})

      case exact || pattern || wildcard do
        fun when is_function(fun) ->
          fun

        nil ->
          registered =
            Enum.map_join(state, "\n", fn {registered_key, value} ->
              " #{inspect(registered_key)} => #{inspect(value)}"
            end)

          example = indent(format_example(module, function, examples), "  ")

          raise """
          Function not found.

            function: #{inspect(function)}
            key: #{inspect(key)}
            pid: #{inspect(self())}

          Found:

          #{registered}

          ---

          You need to register stubs for `#{inspect(function)}` calls.

          #{example}
          """

        other ->
          raise """
          Unrecognized input for #{inspect({function, key})} in #{inspect(self())}.

          Found value:

          #{inspect(other)}

          To fix this, update your test setup:

          #{format_example(module, function, examples)}
          """
      end
    end

    defp match_pattern(state, function, key) do
      Enum.find_value(state, fn
        {{^function, %Regex{} = regex}, fun} -> if Regex.match?(regex, key), do: fun
        _entry -> nil
      end)
    end

    # -------------------------------------------------------------------------
    # Error message construction
    # -------------------------------------------------------------------------

    defp examples(names) do
      first = List.first(names)
      full = Enum.map_join(names, ", ", &to_string/1)

      Enum.uniq(["fn -> ... end", "fn #{first} -> ... end", "fn #{full} -> ... end"])
    end

    defp indent(text, prefix) do
      text
      |> String.split("\n", trim: false)
      |> Enum.map_join("\n", &"#{prefix}#{&1}")
    end

    defp format_example(module, function, examples) do
      """
      alias #{inspect(module)}

      setup do
        #{inspect(module)}.set_#{function}_responses([
          #{Enum.map_join(examples, "\n    # or\n", &("    " <> &1))}
          # or
          {~r|pattern|, fn -> _response end}
        ])
      end
      """
    end

    defp raise_unsupported_arity(fun, examples) do
      raise """
      This function's signature is not supported: #{inspect(fun)}

      Please provide a function with one of the following arities (0-#{length(examples) - 1}):

      #{Enum.map_join(examples, "\n", &("    " <> &1))}
      """
    end

    defp raise_not_started!(module) do
      raise """
      Registry not started for #{inspect(module)}.

      To fix this, add the following line to your `test_helper.exs`:

          #{inspect(module)}.start_link()
      """
    end
  end
end
