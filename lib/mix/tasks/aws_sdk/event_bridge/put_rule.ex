defmodule Mix.Tasks.AwsSDK.Eventbridge.PutRule do
  @shortdoc "Creates or updates an EventBridge rule"

  @moduledoc """
  Creates an EventBridge rule. Skips if the rule already exists unless `--force` is given.

  ## Usage

      mix aws_sdk.eventbridge.put_rule RULE [options]

  ## Options

    * `--event-pattern` — JSON event pattern string (required unless `--schedule`)
    * `--schedule` — Schedule expression (e.g. `rate(5 minutes)` or `cron(0 12 * * ? *)`)
    * `--state` — `ENABLED` or `DISABLED` (default: `ENABLED`)
    * `--description` — Human-readable description
    * `--role-arn` — IAM role ARN for EventBridge to assume
    * `--event-bus-name` — Custom event bus name
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)
    * `--force` / `-f` — Update the rule if it already exists

  ## Examples

      mix aws_sdk.eventbridge.put_rule my-rule --event-pattern '{"source":["aws.s3"]}'
      mix aws_sdk.eventbridge.put_rule my-rule --event-pattern '{"source":["aws.s3"]}' --force
      mix aws_sdk.eventbridge.put_rule my-rule --schedule 'rate(5 minutes)' --state DISABLED
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
        event_pattern: :string,
        schedule: :string,
        state: :string,
        description: :string,
        role_arn: :string
      )

    rule = List.first(args) || Mix.raise("Usage: mix aws_sdk.eventbridge.put_rule RULE [options]")
    opts = Helpers.build_opts(parsed)
    force = parsed[:force] || false

    event_pattern =
      case parsed[:event_pattern] do
        nil -> nil
        json -> :json.decode(json)
      end

    rule_opts =
      opts
      |> Helpers.maybe_put(:event_pattern, event_pattern)
      |> Helpers.maybe_put(:schedule_expression, parsed[:schedule])
      |> Helpers.maybe_put(:state, parsed[:state])
      |> Helpers.maybe_put(:description, parsed[:description])
      |> Helpers.maybe_put(:role_arn, parsed[:role_arn])

    Helpers.idempotent(
      rule,
      fn -> AwsSDK.EventBridge.describe_rule(rule, opts) end,
      fn ->
        Helpers.handle_result(AwsSDK.EventBridge.put_rule(rule, rule_opts))
      end,
      force
    )
  end
end
