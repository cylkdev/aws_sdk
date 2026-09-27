defmodule Mix.Tasks.AwsSDK.IdentityCenter.ListInstances do
  @shortdoc "Lists IAM Identity Center instances"

  @moduledoc """
  Lists IAM Identity Center instances accessible in the current AWS account.

  Returns instance ARNs and identity store IDs needed for other Identity Center
  operations.

  ## Usage

      mix aws_sdk.identity_center.list_instances [options]

  ## Options

    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.identity_center.list_instances
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
    {parsed, _args, _} = Helpers.parse_opts(argv)
    opts = Helpers.build_opts(parsed)

    opts
    |> AwsSDK.IdentityCenter.list_instances()
    |> Helpers.handle_result()
  end
end
