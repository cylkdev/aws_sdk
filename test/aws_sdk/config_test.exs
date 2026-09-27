defmodule AwsSDK.ConfigTest do
  use ExUnit.Case, async: false

  alias AwsSDK.AuthCache
  alias AwsSDK.Config

  setup do
    # Each test starts with a clean slate: no env creds, no app-env creds,
    # no cached IMDS/ECS/awscli entries, and shared-config paths pointed at
    # files that do not exist so the machine's real ~/.aws cannot leak in.
    # Anything we observe then comes from what the test sets up.
    env_keys = [
      "AWS_PROFILE",
      "AWS_ACCESS_KEY_ID",
      "AWS_SECRET_ACCESS_KEY",
      "AWS_SESSION_TOKEN",
      "AWS_REGION",
      "AWS_DEFAULT_REGION",
      "AWS_CONFIG_FILE",
      "AWS_SHARED_CREDENTIALS_FILE"
    ]

    app_env_keys = [
      :credentials,
      :access_key_id,
      :secret_access_key,
      :security_token,
      :region,
      :sandbox
    ]

    prior_env = Enum.map(env_keys, &{&1, System.get_env(&1)})
    prior_app_env = Enum.map(app_env_keys, &{&1, Application.get_env(:aws_sdk, &1)})

    for var <- env_keys, do: System.delete_env(var)
    for key <- app_env_keys, do: Application.delete_env(:aws_sdk, key)

    absent = Path.join(System.tmp_dir!(), "aws-config-test-absent-#{System.unique_integer()}")
    System.put_env("AWS_CONFIG_FILE", absent)
    System.put_env("AWS_SHARED_CREDENTIALS_FILE", absent)

    AuthCache.clear()

    on_exit(fn ->
      for {var, value} <- prior_env do
        if value, do: System.put_env(var, value), else: System.delete_env(var)
      end

      for {key, value} <- prior_app_env do
        if is_nil(value),
          do: Application.delete_env(:aws_sdk, key),
          else: Application.put_env(:aws_sdk, key, value)
      end

      AuthCache.clear()
    end)

    :ok
  end

  # A source that mints a distinct credential set per call, like SSO
  # GetRoleCredentials and STS AssumeRole do.
  defp minter do
    counter = :counters.new(1, [])

    fn _opts ->
      :counters.add(counter, 1, 1)
      Process.sleep(50)
      mint = :counters.get(counter, 1)

      {:ok,
       %{
         access_key_id: "AKIA_#{mint}",
         secret_access_key: "secret_#{mint}",
         security_token: "token_#{mint}",
         region: "eu-west-1"
       }}
    end
  end

  describe "credentials resolve as one unit" do
    test "concurrent cold-start resolutions never mix two mints" do
      # The regression: one mint's access key paired with another mint's
      # session token, which AWS rejects with InvalidClientTokenId.
      fetcher = minter()

      resolved =
        1..20
        |> Task.async_stream(fn _ -> Config.new(fetcher: fetcher) end,
          max_concurrency: 20,
          timeout: 5_000
        )
        |> Enum.map(fn {:ok, result} -> result end)

      for creds <- resolved do
        assert ["AKIA", mint] = String.split(creds[:access_key_id], "_")
        assert creds[:secret_access_key] === "secret_#{mint}"
        assert creds[:security_token] === "token_#{mint}"
      end

      assert 1 === resolved |> Enum.uniq() |> length()
    end

    test "new/1 resolves the whole set from a single source" do
      resolved = Config.new(fetcher: minter())

      assert "AKIA_1" === resolved[:access_key_id]
      assert "secret_1" === resolved[:secret_access_key]
      assert "token_1" === resolved[:security_token]
      assert "eu-west-1" === resolved[:region]
    end

    test "a source missing its secret is skipped rather than half-used" do
      # Only the key is exported; the set is incomplete, so the chain moves on.
      System.put_env("AWS_ACCESS_KEY_ID", "AKIA_PARTIAL")
      on_exit(fn -> System.delete_env("AWS_ACCESS_KEY_ID") end)

      Application.put_env(:aws_sdk, :credentials, [:env, :app_env])
      Application.put_env(:aws_sdk, :access_key_id, "AKIA_APP")
      Application.put_env(:aws_sdk, :secret_access_key, "secret_app")

      resolved = Config.new()

      assert "AKIA_APP" === resolved[:access_key_id]
      assert "secret_app" === resolved[:secret_access_key]
    end
  end

  describe ":env source" do
    test "yields the exported pair plus the session token" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIA_ENV")
      System.put_env("AWS_SECRET_ACCESS_KEY", "secret_env")
      System.put_env("AWS_SESSION_TOKEN", "token_env")

      Application.put_env(:aws_sdk, :credentials, [:env])

      resolved = Config.new()

      assert "AKIA_ENV" === resolved[:access_key_id]
      assert "secret_env" === resolved[:secret_access_key]
      assert "token_env" === resolved[:security_token]
    end

    test "treats empty-string env vars as unset" do
      System.put_env("AWS_ACCESS_KEY_ID", "")
      System.put_env("AWS_SECRET_ACCESS_KEY", "")

      Application.put_env(:aws_sdk, :credentials, [:env])

      assert is_nil(Config.access_key_id())
    end

    test "trims whitespace around env values" do
      System.put_env("AWS_ACCESS_KEY_ID", "  AKIA_PADDED  ")
      System.put_env("AWS_SECRET_ACCESS_KEY", "  secret_padded  ")

      Application.put_env(:aws_sdk, :credentials, [:env])

      assert "AKIA_PADDED" === Config.access_key_id()
      assert "secret_padded" === Config.secret_access_key()
    end
  end

  describe ":app_env source" do
    test "yields the configured pair" do
      Application.put_env(:aws_sdk, :access_key_id, "AKIA_APP")
      Application.put_env(:aws_sdk, :secret_access_key, "secret_app")

      assert "AKIA_APP" === Config.access_key_id()
      assert "secret_app" === Config.secret_access_key()
    end

    test "is skipped when only one half is configured" do
      Application.put_env(:aws_sdk, :access_key_id, "AKIA_APP")

      assert is_nil(Config.access_key_id())
    end
  end

  describe "chain walking" do
    test "the first complete source wins" do
      System.put_env("AWS_ACCESS_KEY_ID", "AKIA_ENV")
      System.put_env("AWS_SECRET_ACCESS_KEY", "secret_env")

      Application.put_env(:aws_sdk, :access_key_id, "AKIA_APP")
      Application.put_env(:aws_sdk, :secret_access_key, "secret_app")
      Application.put_env(:aws_sdk, :credentials, [:env, :app_env])

      assert "AKIA_ENV" === Config.access_key_id()
    end

    test "a literal map is a valid source" do
      Application.put_env(:aws_sdk, :credentials, [
        %{access_key_id: "AKIA_MAP", secret_access_key: "secret_map"}
      ])

      assert "AKIA_MAP" === Config.access_key_id()
    end

    test "unresolved creds remain nil; region falls back to 'us-east-1'" do
      resolved = Config.new()

      assert "us-east-1" === resolved[:region]
      assert is_nil(resolved[:access_key_id])
      assert is_nil(resolved[:secret_access_key])
    end
  end

  describe "precedence (per-call > app env > defaults)" do
    test "a per-call pair beats app env" do
      Application.put_env(:aws_sdk, :access_key_id, "AKIA_APP")
      Application.put_env(:aws_sdk, :secret_access_key, "secret_app")

      resolved = Config.new(access_key_id: "AKIA_CALL", secret_access_key: "secret_call")

      assert "AKIA_CALL" === resolved[:access_key_id]
      assert "secret_call" === resolved[:secret_access_key]
    end

    test "a lone per-call key raises rather than mixing sources" do
      assert_raise ArgumentError, ~r/must be given together/, fn ->
        Config.new(access_key_id: "AKIA_CALL")
      end

      assert_raise ArgumentError, ~r/must be given together/, fn ->
        Config.new(secret_access_key: "secret_call")
      end
    end

    test "app env beats built-in defaults" do
      Application.put_env(:aws_sdk, :region, "ap-southeast-2")

      assert "ap-southeast-2" === Config.region()
    end
  end

  describe "per-call :profile" do
    test "a blank or nil profile falls back to the normal chain" do
      Application.put_env(:aws_sdk, :access_key_id, "AKIA_FROM_APP_ENV")
      Application.put_env(:aws_sdk, :secret_access_key, "secret_from_app_env")

      assert "AKIA_FROM_APP_ENV" === Config.access_key_id(profile: "")
      assert "AKIA_FROM_APP_ENV" === Config.access_key_id(profile: nil)
    end

    test "a named profile replaces the chain entirely" do
      # App-env creds must not leak in when a profile is named.
      Application.put_env(:aws_sdk, :access_key_id, "AKIA_FROM_APP_ENV")
      Application.put_env(:aws_sdk, :secret_access_key, "secret_from_app_env")

      assert "AKIA_1" === Config.access_key_id(profile: "some-profile", fetcher: minter())
    end
  end

  describe "region/1" do
    test "uses the env chain when no opts are supplied" do
      System.put_env("AWS_REGION", "sa-east-1")

      assert "sa-east-1" === Config.region()
    end

    test "prefers AWS_REGION over AWS_DEFAULT_REGION" do
      System.put_env("AWS_REGION", "primary-region")
      System.put_env("AWS_DEFAULT_REGION", "fallback-region")

      assert "primary-region" === Config.region()
    end

    test "respects an explicit opts override" do
      assert "us-west-2" === Config.region(region: "us-west-2")
    end

    test "app env accepts a chain" do
      System.put_env("AWS_TEST_REGION", "eu-central-1")
      on_exit(fn -> System.delete_env("AWS_TEST_REGION") end)

      Application.put_env(:aws_sdk, :region, [
        {:system, "AWS_TEST_MISSING"},
        {:system, "AWS_TEST_REGION"}
      ])

      assert "eu-central-1" === Config.region()
    end

    test "the resolved credential set supplies the region when nothing else does" do
      assert "eu-west-1" === Config.new(fetcher: minter())[:region]
    end

    test "the credential set's region beats AWS_REGION" do
      # A named profile's region is more specific than the ambient env,
      # matching the pre-existing chain order.
      System.put_env("AWS_REGION", "us-west-1")

      assert "eu-west-1" === Config.new(fetcher: minter())[:region]
    end

    test "falls back to 'us-east-1' when everything is unset" do
      assert "us-east-1" === Config.region()
    end
  end

  describe "sandbox/1" do
    test "returns the built-in defaults with no overrides" do
      assert false === Config.sandbox()[:enabled]
    end

    test "app env overrides defaults" do
      Application.put_env(:aws_sdk, :sandbox, enabled: true)

      assert true === Config.sandbox()[:enabled]
    end

    test "caller opts override app env" do
      Application.put_env(:aws_sdk, :sandbox, enabled: false)

      assert true === Config.sandbox(sandbox: [enabled: true])[:enabled]
    end
  end
end
