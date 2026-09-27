defmodule Mix.Tasks.AwsSDK.Eventbridge.DescribeRule do
  @shortdoc "Shows details about an EventBridge rule"

  @moduledoc """
  Returns details about an EventBridge rule.

  ## Usage

      mix aws_sdk.eventbridge.describe_rule RULE [options]

  ## Options

    * `--event-bus-name` — Custom event bus name
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.eventbridge.describe_rule my-rule
      mix aws_sdk.eventbridge.describe_rule my-rule --region us-east-1
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
    {parsed, args, _} = Helpers.parse_opts(argv)

    rule = List.first(args) || Mix.raise("Usage: mix aws_sdk.eventbridge.describe_rule RULE")
    opts = Helpers.build_opts(parsed)

    rule
    |> AwsSDK.EventBridge.describe_rule(opts)
    |> Helpers.handle_result()
  end
end
