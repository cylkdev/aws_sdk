defmodule AwsSDK.AuthCache do
  @moduledoc """
  ETS-backed credential cache for the runtime-resolved sources consumed
  by `AwsSDK.Config`: `:instance_role`, `:ecs_task_role`, and
  `{:awscli, profile}`.

  Keys:

    * `:aws_instance_auth` — EC2 IMDSv2 credentials.
    * `:aws_ecs_auth` — ECS container credentials.
    * `{:awscli, profile_name}` — shared-profile dispatch (static /
      SSO / credential_process / assume_role).

  ## Single-flight

  A cached entry is read straight from ETS in the calling process, so
  the hot path costs one `:ets.lookup/2`.

  A *miss* is serialised through the GenServer, which runs at most one
  fetch per key at a time and replies to every waiter with the same
  result. This matters because the fetchers mint credentials rather
  than read them: SSO `GetRoleCredentials` and STS `AssumeRole` return
  a different key/secret/token triple on every call. Without
  single-flight, N processes starting concurrently on a cold cache each
  mint their own triple and overwrite each other in ETS, which can hand
  a caller one mint's access key alongside another mint's session
  token — a combination AWS rejects with `InvalidClientTokenId`.

  The fetch itself runs in a task spawned by the GenServer, not in the
  GenServer loop, so a slow IMDS timeout or SSO round trip never blocks
  reads or fetches for other keys.

  Failures are not cached: `AwsSDK.Config` resolves a whole credential set
  in one `get/2`, so a failing source costs one fetch, and the next
  call gets a fresh attempt rather than a stale error.

  ## Freshness

  An entry is fresh while it is inside **both** windows:

    * the TTL — `opts[:ttl_seconds]`, defaulting to 30 seconds —
      measured from when it was cached, and
    * its own `:expires_at`, if the source provided one, less a
      60-second refresh skew.

  The remaining keys in `opts` are forwarded verbatim to the fetcher
  (`:http`, `:home_dir`, `:endpoint`, `:endpoints`, `:profile`) so
  caller-supplied overrides reach the HTTP and profile layers.
  """

  use GenServer

  require Logger

  alias AwsSDK.Credentials.Profile
  alias AwsSDK.Credentials.Providers.{ECS, IMDS}

  @table :aws_auth_cache
  @refresh_skew_seconds 60
  @default_ttl_seconds 30

  @type key :: :aws_instance_auth | :aws_ecs_auth | {:awscli, String.t()}
  @type creds :: %{optional(atom) => term}

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Returns the cached credentials for `key`, fetching on a miss or when
  the cached entry has gone stale. Returns `{:error, reason}` when the
  fetcher fails.

  Concurrent misses on the same key share a single fetch and receive
  the same credential map.

  `opts` is forwarded to the fetcher. `opts[:ttl_seconds]` caps the
  cache lifetime.

  ## Examples

      AwsSDK.AuthCache.get({:awscli, "dev"}, [])
      #=> {:ok,
      #=>  %{
      #=>    access_key_id: "ASIA1EXAMPLE",
      #=>    secret_access_key: "...",
      #=>    security_token: "IQoJb3JpZ2luX2VjEJr...",
      #=>    expires_at: ~U[2026-01-01 01:00:00Z],
      #=>    source: :sts
      #=>  }}

      AwsSDK.AuthCache.get({:awscli, "no-such-profile"}, [])
      #=> {:error, :no_credentials}

  Concurrent callers for the same key share one in-flight fetch rather than
  each hitting the provider. A cached entry is refreshed once `:expires_at`
  is near, so a long-running process keeps working without re-authenticating
  on every call.
  """
  @spec get(key, keyword) :: {:ok, creds} | {:error, term}
  def get(key, opts) do
    case lookup(key, opts) do
      {:ok, creds} -> {:ok, creds}
      :error -> GenServer.call(__MODULE__, {:acquire, key, opts}, :infinity)
    end
  end

  @doc """
  Drops every cached entry. Intended for tests.

  ## Examples

      AwsSDK.AuthCache.clear()
      #=> :ok

  Call it between tests that stub different credential sources, so a cached
  entry from an earlier test cannot answer a later one.
  """
  @spec clear :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # ---

  # Returns `{:ok, creds}` only for an entry that is still fresh.
  # Tolerates a missing table so a `get/2` before the supervisor has
  # started degrades into a fetch rather than raising.
  defp lookup(key, opts) do
    with tid when tid !== :undefined <- :ets.whereis(@table),
         [{^key, entry}] <- :ets.lookup(tid, key),
         true <- fresh?(entry, opts[:ttl_seconds]) do
      {:ok, entry.creds}
    else
      _ -> :error
    end
  end

  defp fresh?(entry, ttl_seconds) do
    within_ttl?(entry, ttl_seconds || @default_ttl_seconds) and not near_expiry?(entry)
  end

  defp within_ttl?(%{cached_at: cached_at}, ttl_seconds) do
    System.monotonic_time(:second) - cached_at < ttl_seconds
  end

  defp near_expiry?(%{expires_at: %DateTime{} = expires_at}) do
    DateTime.diff(expires_at, DateTime.utc_now(), :second) <= @refresh_skew_seconds
  end

  defp near_expiry?(_entry), do: false

  # `opts[:fetcher]` is a test seam: it substitutes the provider call so
  # the cache's concurrency behavior can be exercised without a network.
  defp fetch(key, opts) do
    case opts[:fetcher] do
      fun when is_function(fun, 1) -> fun.(opts)
      nil -> fetch_from_provider(key, opts)
    end
  end

  defp fetch_from_provider(:aws_instance_auth, opts), do: IMDS.resolve(opts)
  defp fetch_from_provider(:aws_ecs_auth, opts), do: ECS.resolve(opts)

  defp fetch_from_provider({:awscli, profile}, opts),
    do: Profile.security_credentials(profile, opts)

  defp entry(creds) do
    %{
      creds: creds,
      expires_at: Map.get(creds, :expires_at),
      cached_at: System.monotonic_time(:second)
    }
  end

  # Logs once per real failure. `:skip` is intentionally silent: it just
  # means a provider doesn't apply (no profile, no IMDS, no ECS env
  # vars). Benign per-source failure shapes are filtered out so a
  # non-EC2 dev box doesn't spam the log every time IMDS times out.
  defp log_failure(key, reason) do
    if loggable?(key, reason) do
      Logger.warning(
        "[AwsSDK.AuthCache] credential source #{inspect(key)} failed: " <>
          "#{inspect(reason)} — continuing chain"
      )
    end
  end

  defp loggable?({:awscli, _}, {:profile_not_found, _}), do: false
  defp loggable?(:aws_instance_auth, {:imds_transport_error, _}), do: false
  defp loggable?(:aws_instance_auth, :imds_no_role), do: false
  defp loggable?(_key, _reason), do: true

  # -- GenServer ---------------------------------------------------------------

  @impl GenServer
  def init(:ok) do
    table = :ets.new(@table, [:named_table, :protected, :set, read_concurrency: true])
    {:ok, %{table: table, inflight: %{}}}
  end

  @impl GenServer
  def handle_call({:acquire, key, opts}, from, state) do
    # Re-check under the server: another process may have populated the
    # entry while this call sat in the mailbox, in which case no fetch
    # is needed at all.
    case lookup(key, opts) do
      {:ok, creds} -> {:reply, {:ok, creds}, state}
      :error -> {:noreply, enqueue(state, key, opts, from)}
    end
  end

  def handle_call(:clear, _from, state) do
    true = :ets.delete_all_objects(state.table)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:fetched, key, result}, state) do
    {waiters, inflight} = take_waiters(state, key)

    reply =
      case result do
        {:ok, creds} ->
          true = :ets.insert(state.table, {key, entry(creds)})
          {:ok, creds}

        {:error, reason} ->
          log_failure(key, reason)
          {:error, reason}

        :skip ->
          {:error, :unavailable}
      end

    for waiter <- waiters, do: GenServer.reply(waiter, reply)
    {:noreply, %{state | inflight: inflight}}
  end

  # A fetcher that raised or exited never sent `:fetched`, so the waiters
  # are still parked here. Normal exits arrive after `:fetched` has already
  # cleared the entry, which `take_waiters/2` renders a no-op.
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    case Enum.find(state.inflight, fn {_key, {owner, _waiters}} -> owner === pid end) do
      nil ->
        {:noreply, state}

      {key, {_owner, waiters}} ->
        log_failure(key, reason)

        for waiter <- waiters,
            do: GenServer.reply(waiter, {:error, {:credential_fetch_failed, reason}})

        {:noreply, %{state | inflight: Map.delete(state.inflight, key)}}
    end
  end

  defp enqueue(state, key, opts, from) do
    case state.inflight do
      %{^key => {pid, waiters}} ->
        %{state | inflight: Map.put(state.inflight, key, {pid, [from | waiters]})}

      _no_fetch_running ->
        server = self()
        {pid, _ref} = spawn_monitor(fn -> send(server, {:fetched, key, fetch(key, opts)}) end)
        %{state | inflight: Map.put(state.inflight, key, {pid, [from]})}
    end
  end

  defp take_waiters(state, key) do
    case Map.pop(state.inflight, key) do
      {nil, inflight} -> {[], inflight}
      {{_pid, waiters}, inflight} -> {waiters, inflight}
    end
  end
end
