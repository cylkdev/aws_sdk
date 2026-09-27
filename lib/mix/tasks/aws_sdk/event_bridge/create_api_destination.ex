defmodule Mix.Tasks.AwsSDK.Eventbridge.CreateApiDestination do
  @shortdoc "Creates an EventBridge API destination (webhook endpoint)"

  @moduledoc """
  Creates an EventBridge API destination — an HTTP endpoint that EventBridge
  can deliver events to. Requires an existing connection for authentication.

  Skips if an API destination with the same name already exists unless `--force` is given.

  ## Usage

      mix aws_sdk.eventbridge.create_api_destination NAME CONNECTION_ARN URL HTTP_METHOD [options]

  ## Arguments

    * `NAME` — API destination name (1–64 chars)
    * `CONNECTION_ARN` — ARN of the connection to use for auth
    * `URL` — Full URL of the HTTP endpoint
    * `HTTP_METHOD` — HTTP method: `POST`, `GET`, `PUT`, `PATCH`, `DELETE`, or `HEAD`

  ## Options

    * `--rate-limit` — Max invocations per second (default: no limit)
    * `--description` — Human-readable description
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)
    * `--force` / `-f` — Update if already exists

  ## Examples

      mix aws_sdk.eventbridge.create_api_destination my-dest arn:aws:events:... https://api.example.com/webhook POST
      mix aws_sdk.eventbridge.create_api_destination my-dest arn:... https://... POST --rate-limit 10
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
        rate_limit: :integer,
        description: :string
      )

    [name, connection_arn, url, http_method] =
      case args do
        [n, c, u, m | _] ->
          [n, c, u, m]

        _ ->
          Mix.raise(
            "Usage: mix aws_sdk.eventbridge.create_api_destination NAME CONNECTION_ARN URL HTTP_METHOD"
          )
      end

    opts = Helpers.build_opts(parsed)
    force = parsed[:force] || false

    dest_opts =
      opts
      |> Helpers.maybe_put(:invocation_rate_limit_per_second, parsed[:rate_limit])
      |> Helpers.maybe_put(:description, parsed[:description])

    Helpers.idempotent(
      name,
      fn -> AwsSDK.EventBridge.describe_api_destination(name, opts) end,
      fn ->
        Helpers.handle_result(
          AwsSDK.EventBridge.create_api_destination(
            name,
            connection_arn,
            url,
            http_method,
            dest_opts
          )
        )
      end,
      force
    )
  end
end
