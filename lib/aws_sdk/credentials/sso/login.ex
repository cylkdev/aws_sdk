defmodule AwsSDK.Credentials.SSO.Login do
  @moduledoc """
  OIDC device-code flow for SSO login — the same interactive flow the
  `aws sso login` CLI implements.

  Drives the four OIDC endpoints exposed by
  `AwsSDK.Credentials.SSO.Client`:

    1. `RegisterClient` — when the cache has no valid `clientId`/
       `clientSecret` pair or the registration has expired.
    2. `StartDeviceAuthorization` — obtains a `deviceCode`, `userCode`,
       and `verificationUriComplete`.
    3. Prompt the user, print the verification URL and `userCode`,
       and attempt to open the URL in a browser.
    4. Poll `CreateToken` with the device-code grant until the user
       approves (or the device code expires).

  On success the full token payload — including `refreshToken`,
  `clientId`, `clientSecret`, and `registrationExpiresAt` — is written
  through `AwsSDK.Credentials.SSO.TokenCache` so subsequent background
  refreshes can rotate the access token without user interaction.
  """

  require Logger

  alias AwsSDK.Credentials.Secrets
  alias AwsSDK.Credentials.{ProcessCreds, Profile}
  alias AwsSDK.Credentials.SSO
  alias AwsSDK.Credentials.SSO.{Operation, TokenCache}

  @client_name_prefix "aws-elixir"
  @content_type {"content-type", "application/json"}
  @accept {"accept", "application/json"}

  @type login_opts :: keyword
  @type result :: {:ok, map} | {:error, term}

  @doc """
  Runs the device-code flow for `profile_name`.

  On success, returns `{:ok, calls}`: one key per step, each holding what
  that step received —

    * `:token_cache_read` — the cache file read while looking for a
      reusable client registration (`nil` when there was none),
    * `:register_client` — `%{body:, headers:}` (only when a new
      registration was needed),
    * `:start_device_authorization` — `%{body:, headers:}`,
    * `:open_browser` — `%{command:, output:, exit_status:}`, `:skipped`,
      or `%{command:, exception:}`,
    * `:create_token` — every polled `%{status_code:, body:, headers:}`, in order,
    * `:token_cache_write` — the cache contents written to disk.

  ## Examples

      AwsSDK.Credentials.SSO.Login.run("dev")
      # Prints the verification URL and code, then polls until you approve:
      #
      #   Attempting to open https://device.sso.us-east-1.amazonaws.com/ ...
      #   Then enter the code: ABCD-EFGH
      #
      #=> {:ok,
      #=>  %{
      #=>    token_cache_read: {:error, :enoent},
      #=>    register_client: %{body: %{"clientId" => "...", ...}, headers: [...]},
      #=>    start_device_authorization: %{body: %{"userCode" => "ABCD-EFGH", ...}, headers: [...]},
      #=>    open_browser: %{command: "open", args: ["..."], stdout: "", stderr: "", exit_status: 0},
      #=>    create_token: [%{status_code: 400, ...}, %{status_code: 200, ...}],
      #=>    token_cache_write: %{"accessToken" => "eyJlbmMiOiJBMjU2R0NN...", ...}
      #=>  }}

      AwsSDK.Credentials.SSO.Login.run("no-such-profile")
      #=> {:error, {:profile_not_found, "no-such-profile"}}

  A failure after any call returns `{:error, {reason, calls}}`, where
  `calls` holds every step result received before the failure.

  The token is written to `~/.aws/sso/cache` before returning. A failed
  write is reported as an error rather than success, because reporting
  success would tell you that you are logged in while the next command finds
  no token.
  """
  @spec run(String.t(), login_opts) :: result
  def run(profile_name, opts \\ []) when is_binary(profile_name) do
    with {:ok, profile} <- load_profile(profile_name, opts),
         {:ok, config} <- extract_config(profile, opts) do
      config |> login(opts) |> Secrets.strip()
    end
  end

  # Each step's result is added to `calls` under its own key. A failure
  # returns `{:error, {reason, calls}}`, so everything received before the
  # failing step is kept.
  defp login(config, opts) do
    case ensure_registration(config, opts) do
      {:error, {reason, calls}} ->
        {:error, {reason, calls}}

      {:ok, registration, calls} ->
        case start_device_auth(registration, config, opts) do
          {:error, reason} ->
            {:error, {reason, calls}}

          {:ok, device, device_resp} ->
            calls = Map.put(calls, :start_device_authorization, device_resp)
            {:ok, browser} = prompt_user(device, opts)
            calls = Map.put(calls, :open_browser, browser)

            case poll_for_token(registration, device, config, opts) do
              {:error, {reason, token_resps}} ->
                {:error, {reason, Map.put(calls, :create_token, token_resps)}}

              {:ok, token, token_resps} ->
                calls = Map.put(calls, :create_token, token_resps)
                cache = build_cache(config, registration, token)

                # Persisting the token is the point of logging in. If the
                # write fails, reporting success would tell the user they are
                # logged in while the next command finds no token.
                case TokenCache.write(config.cache_key, cache, opts) do
                  :ok ->
                    {:ok, Map.put(calls, :token_cache_write, cache)}

                  {:error, reason} ->
                    {:error, {reason, Map.put(calls, :token_cache_write, cache)}}
                end
            end
        end
    end
  end

  @doc """
  Prompts the user on stdin to confirm an interactive login. Returns
  `{:ok, %{answer: line}}` when the user accepts (`answer: :noninteractive`
  when no tty was prompted), `{:error, {:sso_login_declined, answer}}`
  otherwise, where `answer` is the line read, `:eof`, `:timeout`, or
  `:noninteractive`.

  Honors `auto_sso_login_noninteractive`: when stdin is not a tty,
  returns `:ok` only if the opt is truthy.

  ## Examples

      AwsSDK.Credentials.SSO.Login.confirm("dev")
      # AWS SSO credentials for profile dev have expired.
      # Run interactive login now? [Y/n]
      #=> {:ok, %{answer: "y\n"}}

      # Declined, EOF, or no answer within 60 seconds:
      #=> {:error, {:sso_login_declined, :timeout}}

  When stdin is not a tty there is nobody to prompt, so this declines unless
  `auto_sso_login_noninteractive` is truthy -- otherwise a CI run would hang
  on a prompt no one can answer.
  """
  @spec confirm(String.t(), login_opts) :: {:ok, map} | {:error, term}
  def confirm(profile_name, opts \\ []) do
    if tty?() do
      prompt =
        "AWS SSO credentials for profile #{profile_name} have expired. Run interactive login now? [Y/n] "

      case gets_with_timeout(prompt, 60_000) do
        :timeout -> {:error, {:sso_login_declined, :timeout}}
        :eof -> {:error, {:sso_login_declined, :eof}}
        answer -> interpret_confirmation(answer)
      end
    else
      if noninteractive_allowed?(opts) do
        {:ok, %{answer: :noninteractive}}
      else
        {:error, {:sso_login_declined, :noninteractive}}
      end
    end
  end

  defp interpret_confirmation(answer) do
    trimmed = answer |> String.trim() |> String.downcase()

    if trimmed in ["", "y", "yes"] do
      {:ok, %{answer: answer}}
    else
      {:error, {:sso_login_declined, answer}}
    end
  end

  defp noninteractive_allowed?(opts) do
    Keyword.get(
      opts,
      :auto_sso_login_noninteractive,
      config_flag(:auto_sso_login_noninteractive, false)
    )
  end

  defp config_flag(key, default) do
    :aws_sdk
    |> Application.get_env(:credentials, [])
    |> Keyword.get(key, default)
  end

  defp load_profile(profile_name, opts) do
    case Profile.load(profile_name, opts) do
      nil -> {:error, {:profile_not_found, profile_name}}
      profile -> {:ok, profile}
    end
  end

  defp extract_config(profile, opts) do
    cond do
      session_name = Profile.value(profile, "sso_session") ->
        case Profile.load_sso_session(session_name, opts) do
          %{section: nil} = file ->
            {:error, {:sso_session_not_found, session_name, file}}

          %{section: session} ->
            finalize_config(session["sso_start_url"], session["sso_region"], session_name)
        end

      Profile.value(profile, "sso_start_url") ->
        finalize_config(
          Profile.value(profile, "sso_start_url"),
          Profile.value(profile, "sso_region"),
          Profile.value(profile, "sso_start_url")
        )

      true ->
        {:error, :sso_not_configured}
    end
  end

  defp finalize_config(nil, _region, _key), do: {:error, :sso_start_url_missing}
  defp finalize_config(_url, nil, _key), do: {:error, :sso_region_missing}

  defp finalize_config(start_url, region, cache_key) do
    {:ok, %{start_url: start_url, region: region, cache_key: cache_key}}
  end

  defp ensure_registration(config, opts) do
    # The read result is kept as returned, `{:error, _}` included; a missing
    # or unreadable cache just means a fresh registration.
    read = TokenCache.read(config.cache_key, opts)
    calls = %{token_cache_read: read}

    with {:ok, existing} <- read,
         true <- registration_valid?(existing) do
      {:ok, Map.take(existing, ["clientId", "clientSecret", "registrationExpiresAt"]), calls}
    else
      _ ->
        case register(config, opts) do
          {:ok, registration, response} ->
            {:ok, registration, Map.put(calls, :register_client, response)}

          {:error, reason} ->
            {:error, {reason, calls}}
        end
    end
  end

  defp registration_valid?(%{
         "clientId" => id,
         "clientSecret" => secret,
         "registrationExpiresAt" => exp
       })
       when is_binary(id) and is_binary(secret) and is_binary(exp) do
    case DateTime.from_iso8601(exp) do
      {:ok, dt, _} -> DateTime.diff(dt, DateTime.utc_now(), :second) > 0
      _ -> false
    end
  end

  defp registration_valid?(_), do: false

  defp register(config, opts) do
    client_name = "#{@client_name_prefix}-#{hostname()}-#{System.system_time(:second)}"

    body = %{
      "clientName" => client_name,
      "clientType" => "public",
      "scopes" => ["sso:account:access"]
    }

    op = oidc_op("/client/register", body, config.region, opts)
    response = SSO.execute(op)

    case interpret_oidc_response(response, fn _ -> nil end) do
      {:ok, body} ->
        {:ok, %{headers: headers}} = response

        expires_at =
          body["clientSecretExpiresAt"]
          |> DateTime.from_unix!(:second)
          |> DateTime.to_iso8601()

        {:ok,
         %{
           "clientId" => body["clientId"],
           "clientSecret" => body["clientSecret"],
           "registrationExpiresAt" => expires_at
         }, %{body: body, headers: headers}}

      {:error, _} = err ->
        err
    end
  end

  defp hostname do
    {:ok, name} = :inet.gethostname()
    List.to_string(name)
  end

  defp start_device_auth(registration, config, opts) do
    body = %{
      "clientId" => registration["clientId"],
      "clientSecret" => registration["clientSecret"],
      "startUrl" => config.start_url
    }

    op = oidc_op("/device_authorization", body, config.region, opts)
    response = SSO.execute(op)

    case interpret_oidc_response(response, fn _ -> nil end) do
      {:ok, body} ->
        {:ok, %{headers: headers}} = response

        {:ok,
         %{
           device_code: body["deviceCode"],
           user_code: body["userCode"],
           verification_uri: body["verificationUri"],
           verification_uri_complete: body["verificationUriComplete"],
           expires_in: body["expiresIn"] || 600,
           interval: body["interval"] || 5
         }, %{body: body, headers: headers}}

      {:error, _} = err ->
        err
    end
  end

  defp prompt_user(device, opts) do
    uri = device.verification_uri_complete || device.verification_uri

    Logger.info("AWS SSO: open #{uri} in your browser and confirm code #{device.user_code}")

    if opts[:skip_browser_open], do: {:ok, :skipped}, else: {:ok, open_browser(uri)}
  end

  defp open_browser(uri) do
    {bin, args} =
      case :os.type() do
        {:unix, :darwin} -> {"open", [uri]}
        {:unix, _} -> {"xdg-open", [uri]}
        {:win32, _} -> {"cmd", ["/c", "start", uri]}
      end

    # The URL and code were already printed, so failing to auto-open a
    # browser is not fatal -- but it should not look like it worked.
    try do
      result = ProcessCreds.cmd(bin, args)

      if result.exit_status !== 0 do
        Logger.debug("AWS SSO: #{bin} exited #{result.exit_status}: #{inspect(result.stderr)}")
      end

      result
    rescue
      err -> %{command: bin, args: args, exception: err}
    catch
      kind, reason -> %{command: bin, args: args, exception: {kind, reason}}
    end
  end

  defp poll_for_token(registration, device, config, opts) do
    deadline = System.monotonic_time(:second) + device.expires_in
    poll_loop(registration, device, config, opts, deadline, device.interval, [])
  end

  # Every CreateToken response (pending ones included) is kept, in order.
  defp poll_loop(registration, device, config, opts, deadline, interval, responses) do
    if System.monotonic_time(:second) >= deadline do
      {:error, {:sso_login_aborted, Enum.reverse(responses)}}
    else
      :timer.sleep(interval * 1_000)

      body = %{
        "clientId" => registration["clientId"],
        "clientSecret" => registration["clientSecret"],
        "grantType" => "urn:ietf:params:oauth:grant-type:device_code",
        "deviceCode" => device.device_code
      }

      op = oidc_op("/token", body, config.region, opts)
      response = SSO.execute(op)

      responses =
        case response do
          {:ok, resp} -> [resp | responses]
          {:error, _} = err -> [err | responses]
        end

      case interpret_oidc_response(response, device_error(interval)) do
        {:ok, body} ->
          {:ok, body, Enum.reverse(responses)}

        {:pending, new_interval} ->
          poll_loop(registration, device, config, opts, deadline, new_interval, responses)

        {:error, reason} ->
          {:error, {reason, Enum.reverse(responses)}}
      end
    end
  end

  defp build_cache(config, registration, token) do
    expires_in = token["expiresIn"] || 0
    expires_at = DateTime.utc_now() |> DateTime.add(expires_in, :second) |> DateTime.to_iso8601()

    base = %{
      "startUrl" => config.start_url,
      "region" => config.region,
      "accessToken" => token["accessToken"],
      "expiresAt" => expires_at,
      "clientId" => registration["clientId"],
      "clientSecret" => registration["clientSecret"],
      "registrationExpiresAt" => registration["registrationExpiresAt"]
    }

    maybe_put(base, "refreshToken", token["refreshToken"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp tty? do
    case :io.getopts(:standard_io) do
      opts when is_list(opts) -> Keyword.get(opts, :terminal, false) === true
      _ -> false
    end
  end

  defp oidc_op(path, body, region, opts) do
    %Operation{
      method: :post,
      url: oidc_endpoint(region, opts) <> path,
      headers: [@content_type, @accept],
      body: body |> :json.encode() |> IO.iodata_to_binary(),
      http: Keyword.get(opts, :http, [])
    }
  end

  defp oidc_endpoint(region, opts) do
    (opts[:endpoints] || [])[:oidc] || "https://oidc.#{region}.amazonaws.com"
  end

  defp interpret_oidc_response({:ok, %{status_code: 200, body: resp_body}}, _err_fn) do
    decode(resp_body)
  end

  defp interpret_oidc_response({:ok, %{status_code: 400, body: resp_body}}, err_fn) do
    case decode(resp_body) do
      {:ok, %{"error" => code} = err_body} ->
        err_fn.({code, err_body}) || {:error, {:sso_oidc_error, code, err_body}}

      _ ->
        {:error, {:sso_oidc_error, 400, resp_body}}
    end
  end

  defp interpret_oidc_response({:ok, %{status_code: 401} = response}, _err_fn) do
    {:error, {:sso_token_expired, response}}
  end

  defp interpret_oidc_response({:ok, %{status_code: status, body: resp_body}}, _err_fn) do
    {:error, {:sso_oidc_error, status, resp_body}}
  end

  defp interpret_oidc_response({:error, _} = err, _err_fn), do: err

  defp device_error(interval) do
    fn
      {"authorization_pending", _} -> {:pending, interval}
      {"slow_down", _} -> {:pending, interval + 5}
      {"expired_token", err_body} -> {:error, {:sso_login_aborted, err_body}}
      {"access_denied", err_body} -> {:error, {:sso_login_aborted, err_body}}
      _ -> nil
    end
  end

  defp decode(binary) do
    {:ok, :json.decode(binary)}
  rescue
    err -> {:error, {:sso_invalid_json, Exception.message(err)}}
  end

  defp gets_with_timeout(prompt, timeout_ms) do
    parent = self()
    ref = make_ref()

    pid =
      spawn(fn ->
        send(parent, {ref, IO.gets(prompt)})
      end)

    receive do
      {^ref, :eof} -> :eof
      {^ref, {:error, _}} -> :eof
      {^ref, line} when is_binary(line) -> line
    after
      timeout_ms ->
        Process.exit(pid, :kill)
        :timeout
    end
  end
end
