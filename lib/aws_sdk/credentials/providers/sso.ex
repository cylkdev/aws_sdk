defmodule AwsSDK.Credentials.Providers.SSO do
  @moduledoc """
  Resolves AWS Identity Center (SSO) credentials.

  Supports both profile forms:

    * **Modern** (`sso_session`) — the profile names an `[sso-session
      NAME]` block in `~/.aws/config`, which carries `sso_region` and
      `sso_start_url`. The token cache file is keyed by the session
      name.

    * **Legacy** (`sso_start_url` directly on the profile) — pre-CLI
      v2.9 layout. The token cache file is keyed by the start URL.

  Flow:

    1. Load the profile, extract `sso_account_id`, `sso_role_name`, and
       the token-cache key plus region.
    2. Read the token cache. Missing cache file means the user has not
       logged in (or the auto device-code flow is needed).
    3. If the cached `accessToken` is within 5 minutes of `expiresAt`
       and the cache has refresh material (`refreshToken`, `clientId`,
       `clientSecret`, valid `registrationExpiresAt`), exchange the
       refresh token for a new access token and write the updated cache
       atomically.
    4. Call `GetRoleCredentials` on the portal endpoint using the
       access token as a bearer token.

  Returns `{:error, :sso_token_expired}` when the token is stale and
  no refresh is possible. Callers that opt into `auto_sso_login` can
  recover by invoking `AwsSDK.Credentials.SSO.Login`.
  """

  require Logger

  alias AwsSDK.Credentials.Profile
  alias AwsSDK.Credentials.SSO
  alias AwsSDK.Credentials.SSO.{Operation, TokenCache}

  @refresh_skew_seconds 300
  @content_type {"content-type", "application/json"}
  @accept {"accept", "application/json"}

  @doc false
  def resolve(opts) do
    profile_name = opts[:profile] || Profile.default()

    with {:ok, profile} <- require_profile(profile_name, opts),
         {:ok, config} <- extract_sso_config(profile, opts),
         {:ok, token} <- load_or_refresh_token(config, opts),
         {:ok, creds} <- fetch_role_credentials(token, config, opts) do
      {:ok, to_creds(creds)}
    end
  end

  defp require_profile(profile_name, opts) do
    case Profile.load(profile_name, opts) do
      nil -> :skip
      profile -> {:ok, profile}
    end
  end

  defp extract_sso_config(profile, opts) do
    account_id = profile["sso_account_id"]
    role_name = profile["sso_role_name"]

    cond do
      is_nil(account_id) or is_nil(role_name) ->
        :skip

      session_name = profile["sso_session"] ->
        from_session(session_name, account_id, role_name, opts)

      start_url = profile["sso_start_url"] ->
        region = profile["sso_region"]
        build_config(start_url, region, account_id, role_name, start_url)

      true ->
        :skip
    end
  end

  defp from_session(session_name, account_id, role_name, opts) do
    case Profile.load_sso_session(session_name, opts) do
      nil ->
        {:error, {:sso_session_not_found, session_name}}

      session ->
        start_url = session["sso_start_url"]
        region = session["sso_region"]
        build_config(start_url, region, account_id, role_name, session_name)
    end
  end

  defp build_config(nil, _region, _account, _role, _key),
    do: {:error, :sso_start_url_missing}

  defp build_config(_start_url, nil, _account, _role, _key),
    do: {:error, :sso_region_missing}

  defp build_config(start_url, region, account_id, role_name, cache_key) do
    {:ok,
     %{
       start_url: start_url,
       region: region,
       account_id: account_id,
       role_name: role_name,
       cache_key: cache_key
     }}
  end

  defp load_or_refresh_token(config, opts) do
    case TokenCache.read(config.cache_key, opts) do
      {:ok, cached} -> maybe_refresh(cached, config, opts)
      {:error, :enoent} -> {:error, :sso_token_expired}
      {:error, {:invalid_json, _} = reason} -> {:error, reason}
      {:error, reason} -> {:error, {:sso_cache_error, reason}}
    end
  end

  defp maybe_refresh(cached, config, opts) do
    if near_expiry?(cached["expiresAt"]) and refresh_material?(cached) do
      refresh_access_token(cached, config, opts)
    else
      case cached["accessToken"] do
        token when is_binary(token) and token !== "" -> {:ok, cached}
        _ -> {:error, :sso_token_expired}
      end
    end
  end

  defp near_expiry?(nil), do: true

  defp near_expiry?(expires_at_iso) do
    case DateTime.from_iso8601(expires_at_iso) do
      {:ok, dt, _} ->
        DateTime.diff(dt, DateTime.utc_now(), :second) <= @refresh_skew_seconds

      _ ->
        true
    end
  end

  defp refresh_material?(cached) do
    is_binary(cached["refreshToken"]) and
      is_binary(cached["clientId"]) and
      is_binary(cached["clientSecret"]) and
      registration_valid?(cached["registrationExpiresAt"])
  end

  defp registration_valid?(nil), do: false

  defp registration_valid?(iso) do
    case DateTime.from_iso8601(iso) do
      {:ok, dt, _} -> DateTime.diff(dt, DateTime.utc_now(), :second) > 0
      _ -> false
    end
  end

  defp refresh_access_token(cached, config, opts) do
    body = %{
      "clientId" => cached["clientId"],
      "clientSecret" => cached["clientSecret"],
      "grantType" => "refresh_token",
      "refreshToken" => cached["refreshToken"]
    }

    op = %Operation{
      method: :post,
      url: oidc_endpoint(config.region, opts) <> "/token",
      headers: [@content_type, @accept],
      body: body |> :json.encode() |> IO.iodata_to_binary(),
      http: Keyword.get(opts, :http, [])
    }

    case interpret_oidc_response(SSO.execute(op), &token_error/1) do
      {:ok, body} ->
        updated = merge_refreshed(cached, body)
        :ok = persist_refreshed(config.cache_key, updated, opts)
        {:ok, updated}

      {:error, _} = err ->
        err
    end
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

  defp interpret_oidc_response({:ok, %{status_code: 401}}, _err_fn) do
    {:error, :sso_token_expired}
  end

  defp interpret_oidc_response({:ok, %{status_code: status, body: resp_body}}, _err_fn) do
    {:error, {:sso_oidc_error, status, resp_body}}
  end

  defp interpret_oidc_response({:error, _} = err, _err_fn), do: err

  defp token_error({"invalid_grant", _}), do: {:error, :sso_token_expired}
  defp token_error({"invalid_client", _}), do: {:error, :sso_token_expired}
  defp token_error(_), do: nil

  defp oidc_endpoint(region, opts) do
    (opts[:endpoints] || [])[:oidc] || "https://oidc.#{region}.amazonaws.com"
  end

  defp decode(binary) do
    {:ok, :json.decode(binary)}
  rescue
    err -> {:error, {:sso_invalid_json, Exception.message(err)}}
  end

  # Unlike `AwsSDK.Credentials.SSO.Login`, this refresh happens while resolving
  # credentials for a call that can still succeed: the new token is valid in
  # memory and is returned. Failing here would turn a read-only cache
  # directory into "no AWS access at all". It is not silent, though — every
  # later process will refresh again, which costs an extra OIDC round trip
  # and can eventually be throttled.
  defp persist_refreshed(cache_key, contents, opts) do
    case TokenCache.write(cache_key, contents, opts) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "[AwsSDK.Credentials.Providers.SSO] could not persist the refreshed SSO token: " <>
            "#{inspect(reason)} — continuing with the in-memory token"
        )
    end
  end

  defp merge_refreshed(cached, %{"accessToken" => access} = body) do
    expires_in = body["expiresIn"] || 0
    new_expiry = DateTime.utc_now() |> DateTime.add(expires_in, :second) |> DateTime.to_iso8601()

    cached
    |> Map.put("accessToken", access)
    |> Map.put("expiresAt", new_expiry)
    |> maybe_put("refreshToken", body["refreshToken"])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp fetch_role_credentials(token, config, opts) do
    url =
      "#{portal_endpoint(config.region, opts)}/federation/credentials" <>
        "?account_id=#{URI.encode_www_form(config.account_id)}" <>
        "&role_name=#{URI.encode_www_form(config.role_name)}"

    op = %Operation{
      method: :get,
      url: url,
      headers: [{"x-amz-sso_bearer_token", token["accessToken"]}, @accept],
      body: "",
      http: Keyword.get(opts, :http, [])
    }

    case SSO.execute(op) do
      {:ok, %{status_code: 200, body: body}} ->
        case decode(body) do
          {:ok, %{"roleCredentials" => creds}} -> {:ok, creds}
          {:ok, other} -> {:error, {:sso_unexpected_body, other}}
          {:error, _} = err -> err
        end

      {:ok, %{status_code: status}} when status in [401, 403] ->
        {:error, :sso_token_expired}

      {:ok, %{status_code: status, body: body}} ->
        {:error, {:sso_http_error, status, body}}

      {:error, _} = err ->
        err
    end
  end

  defp portal_endpoint(region, opts) do
    (opts[:endpoints] || [])[:portal] || "https://portal.sso.#{region}.amazonaws.com"
  end

  defp to_creds(%{"accessKeyId" => ak, "secretAccessKey" => sk} = role_creds) do
    %{
      access_key_id: ak,
      secret_access_key: sk,
      security_token: role_creds["sessionToken"],
      expires_at: unix_ms_to_datetime(role_creds["expiration"]),
      source: :sso
    }
  end

  defp unix_ms_to_datetime(nil), do: nil

  defp unix_ms_to_datetime(ms) when is_integer(ms) do
    case DateTime.from_unix(ms, :millisecond) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  defp unix_ms_to_datetime(_), do: nil
end
