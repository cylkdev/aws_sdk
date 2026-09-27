defmodule Mix.Tasks.AwsSDK.Eventbridge.CreateConnection do
  @shortdoc "Creates an EventBridge connection for API destination auth"

  @moduledoc """
  Creates an EventBridge connection that stores authentication credentials
  for use with API destinations. Skips if a connection with the same name
  already exists unless `--force` is given.

  ## Usage

      mix aws_sdk.eventbridge.create_connection NAME AUTH_TYPE [options]

  ## Arguments

    * `NAME` — Connection name (1–64 chars)
    * `AUTH_TYPE` — One of `api_key`, `basic`, or `oauth`

  ## Options for `api_key` auth:

    * `--api-key-name` — Header name for the API key (required)
    * `--api-key-value` — API key value (required)

  ## Options for `basic` auth:

    * `--username` — Username (required)
    * `--password` — Password (required)

  ## Options for `oauth` auth:

    * `--client-id` — OAuth client ID (required)
    * `--client-secret` — OAuth client secret (required)
    * `--authorization-endpoint` — Token endpoint URL (required)
    * `--http-method` — HTTP method for token requests (default: `POST`)

  ## Shared options:

    * `--description` — Human-readable description
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)
    * `--force` / `-f` — Update the connection if it already exists

  ## Examples

      mix aws_sdk.eventbridge.create_connection my-conn api_key --api-key-name X-API-Key --api-key-value secret
      mix aws_sdk.eventbridge.create_connection my-conn basic --username user --password pass
  """

  use Mix.Task
  alias Mix.Tasks.AwsSDK.Helpers

  # @requirements declares the Mix tasks that must run before this task.
  #
  # When this task is invoked, Mix runs each requirement once with Mix.Task.run/2
  # before calling this task's run/1 function.
  #
  # This makes task dependencies explicit in the task definition instead of
  # requiring run/1 to start dependencies manually or requiring callers to compose
  # tasks themselves.
  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {parsed, args, _} =
      Helpers.parse_opts(argv,
        api_key_name: :string,
        api_key_value: :string,
        username: :string,
        password: :string,
        client_id: :string,
        client_secret: :string,
        authorization_endpoint: :string,
        http_method: :string,
        description: :string
      )

    [name, auth_type] =
      case args do
        [n, t | _] ->
          [n, t]

        _ ->
          Mix.raise("Usage: mix aws_sdk.eventbridge.create_connection NAME AUTH_TYPE [options]")
      end

    opts = Helpers.build_opts(parsed)
    force = parsed[:force] || false
    {authorization_type, auth_parameters} = build_auth(auth_type, parsed)

    create_opts = Helpers.maybe_put(opts, :description, parsed[:description])

    Helpers.idempotent(
      name,
      fn -> AwsSDK.EventBridge.describe_connection(name, opts) end,
      fn ->
        Helpers.handle_result(
          AwsSDK.EventBridge.create_connection(
            name,
            authorization_type,
            auth_parameters,
            create_opts
          )
        )
      end,
      force
    )
  end

  defp build_auth("api_key", parsed) do
    key_name = parsed[:api_key_name] || Mix.raise("--api-key-name is required for api_key auth")

    key_value =
      parsed[:api_key_value] || Mix.raise("--api-key-value is required for api_key auth")

    auth = %{
      "ApiKeyAuthParameters" => %{
        "ApiKeyName" => key_name,
        "ApiKeyValue" => key_value
      }
    }

    {"API_KEY", auth}
  end

  defp build_auth("basic", parsed) do
    username = parsed[:username] || Mix.raise("--username is required for basic auth")
    password = parsed[:password] || Mix.raise("--password is required for basic auth")

    auth = %{
      "BasicAuthParameters" => %{
        "Username" => username,
        "Password" => password
      }
    }

    {"BASIC", auth}
  end

  defp build_auth("oauth", parsed) do
    client_id = parsed[:client_id] || Mix.raise("--client-id is required for oauth auth")

    client_secret =
      parsed[:client_secret] || Mix.raise("--client-secret is required for oauth auth")

    endpoint =
      parsed[:authorization_endpoint] ||
        Mix.raise("--authorization-endpoint is required for oauth auth")

    method = parsed[:http_method] || "POST"

    auth = %{
      "OAuthParameters" => %{
        "ClientParameters" => %{
          "ClientID" => client_id,
          "ClientSecret" => client_secret
        },
        "AuthorizationEndpoint" => endpoint,
        "HttpMethod" => method
      }
    }

    {"OAUTH_CLIENT_CREDENTIALS", auth}
  end

  defp build_auth(type, _),
    do: Mix.raise("Unknown auth type '#{type}'. Use: api_key, basic, oauth")
end
