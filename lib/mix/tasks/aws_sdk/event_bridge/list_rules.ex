defmodule Mix.Tasks.AwsSDK.Eventbridge.ListRules do
  @shortdoc "Lists EventBridge rules"

  @moduledoc """
  Lists EventBridge rules, optionally filtered by name prefix.

  ## Usage

      mix aws_sdk.eventbridge.list_rules [options]

  ## Options

    * `--name-prefix` — Filter rules whose names begin with this string
    * `--event-bus-name` — Custom event bus name
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.eventbridge.list_rules
      mix aws_sdk.eventbridge.list_rules --name-prefix my-s3
      mix aws_sdk.eventbridge.list_rules --event-bus-name my-bus
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
    {parsed, _args, _} = Helpers.parse_opts(argv, name_prefix: :string)

    opts =
      parsed
      |> Helpers.build_opts()
      |> Helpers.maybe_put(:name_prefix, parsed[:name_prefix])

    opts
    |> AwsSDK.EventBridge.list_rules()
    |> Helpers.handle_result()
  end
end
