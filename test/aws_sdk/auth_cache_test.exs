defmodule AwsSDK.AuthCacheTest do
  @moduledoc """
  Regression coverage for the credential-resolution race that produced
  intermittent `InvalidClientTokenId` 403s: concurrent cold-start
  processes each minting their own credential triple and overwriting
  each other in ETS.
  """

  use ExUnit.Case, async: false

  alias AwsSDK.AuthCache

  @key {:awscli, "auth-cache-test"}

  setup do
    AuthCache.clear()
    counter = :counters.new(1, [])
    on_exit(fn -> AuthCache.clear() end)
    {:ok, counter: counter}
  end

  # Each invocation mints a *distinct* credential set, exactly as SSO
  # GetRoleCredentials and STS AssumeRole do.
  defp minter(counter, opts \\ []) do
    fn _fetch_opts ->
      :counters.add(counter, 1, 1)
      Process.sleep(Keyword.get(opts, :sleep, 50))
      mint = :counters.get(counter, 1)

      {:ok,
       %{
         access_key_id: "AKIA_#{mint}",
         secret_access_key: "secret_#{mint}",
         security_token: "token_#{mint}",
         expires_at: opts[:expires_at]
       }}
    end
  end

  defp mints(counter), do: :counters.get(counter, 1)

  describe "single-flight" do
    test "concurrent misses on a cold cache share one fetch", %{counter: counter} do
      results =
        1..20
        |> Task.async_stream(
          fn _ -> AuthCache.get(@key, fetcher: minter(counter)) end,
          max_concurrency: 20,
          timeout: 5_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert mints(counter) === 1, "expected one mint, got #{mints(counter)}"
      assert [{:ok, creds}] = Enum.uniq(results)
      assert creds.access_key_id === "AKIA_1"
    end

    test "every waiter gets a self-consistent credential set", %{counter: counter} do
      # The actual failure mode: a caller holding key A alongside token B.
      results =
        1..20
        |> Task.async_stream(fn _ -> AuthCache.get(@key, fetcher: minter(counter)) end,
          max_concurrency: 20,
          timeout: 5_000
        )
        |> Enum.map(fn {:ok, {:ok, creds}} -> creds end)

      for creds <- results do
        assert ["AKIA", mint] = String.split(creds.access_key_id, "_")
        assert creds.secret_access_key === "secret_#{mint}"
        assert creds.security_token === "token_#{mint}"
      end
    end

    test "a second fetch is not started while one is in flight", %{counter: counter} do
      task = Task.async(fn -> AuthCache.get(@key, fetcher: minter(counter, sleep: 200)) end)
      Process.sleep(50)

      assert {:ok, creds} = AuthCache.get(@key, fetcher: minter(counter, sleep: 200))
      assert {:ok, ^creds} = Task.await(task)
      assert mints(counter) === 1
    end
  end

  describe "freshness" do
    test "a fresh entry is served without re-fetching", %{counter: counter} do
      assert {:ok, first} = AuthCache.get(@key, fetcher: minter(counter))
      assert {:ok, ^first} = AuthCache.get(@key, fetcher: minter(counter))
      assert mints(counter) === 1
    end

    test "an entry without :expires_at still expires with the TTL", %{counter: counter} do
      # Static profiles return expires_at: nil and were previously cached
      # forever.
      fetcher = minter(counter)

      assert {:ok, %{access_key_id: "AKIA_1"}} = AuthCache.get(@key, fetcher: fetcher)
      Process.sleep(1_100)

      assert {:ok, %{access_key_id: "AKIA_2"}} =
               AuthCache.get(@key, fetcher: fetcher, ttl_seconds: 1)

      assert mints(counter) === 2
    end

    test "an entry inside the refresh skew is re-fetched despite the TTL", %{counter: counter} do
      near = DateTime.add(DateTime.utc_now(), 30, :second)
      fetcher = minter(counter, expires_at: near)

      assert {:ok, %{access_key_id: "AKIA_1"}} = AuthCache.get(@key, fetcher: fetcher)
      assert {:ok, %{access_key_id: "AKIA_2"}} = AuthCache.get(@key, fetcher: fetcher)
      assert mints(counter) === 2
    end

    test "an entry well beyond the refresh skew is cached", %{counter: counter} do
      far = DateTime.add(DateTime.utc_now(), 3_600, :second)
      fetcher = minter(counter, expires_at: far)

      assert {:ok, first} = AuthCache.get(@key, fetcher: fetcher)
      assert {:ok, ^first} = AuthCache.get(@key, fetcher: fetcher)
      assert mints(counter) === 1
    end
  end

  describe "failures" do
    test "errors are not cached", %{counter: counter} do
      assert {:error, :boom} = AuthCache.get(@key, fetcher: fn _ -> {:error, :boom} end)
      assert {:ok, %{access_key_id: "AKIA_1"}} = AuthCache.get(@key, fetcher: minter(counter))
    end

    test ":skip surfaces as :unavailable and is not cached", %{counter: counter} do
      assert {:error, :unavailable} = AuthCache.get(@key, fetcher: fn _ -> :skip end)
      assert {:ok, _} = AuthCache.get(@key, fetcher: minter(counter))
      assert mints(counter) === 1
    end

    test "a raising fetcher replies to every waiter and leaves no in-flight entry", %{
      counter: counter
    } do
      boom = fn _ ->
        Process.sleep(50)
        raise "credential provider exploded"
      end

      results =
        1..5
        |> Task.async_stream(fn _ -> AuthCache.get(@key, fetcher: boom) end,
          max_concurrency: 5,
          timeout: 5_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      assert Enum.all?(results, &match?({:error, {:credential_fetch_failed, _}}, &1))

      # The in-flight slot was released, so the cache still works.
      assert {:ok, %{access_key_id: "AKIA_1"}} = AuthCache.get(@key, fetcher: minter(counter))
    end
  end

  test "clear/0 drops cached entries", %{counter: counter} do
    fetcher = minter(counter)

    assert {:ok, %{access_key_id: "AKIA_1"}} = AuthCache.get(@key, fetcher: fetcher)
    assert :ok = AuthCache.clear()
    assert {:ok, %{access_key_id: "AKIA_2"}} = AuthCache.get(@key, fetcher: fetcher)
  end
end
