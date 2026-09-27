defmodule Mix.Tasks.AwsSDK.IAM.RemoveUserFromGroup do
  @shortdoc "Removes an IAM user from a group"

  @moduledoc """
  Removes an IAM user from a group.

  ## Usage

      mix aws_sdk.iam.remove_user_from_group --group GROUP --user USER [options]

  ## Options

    * `--group` — Group name (required)
    * `--user` — User name (required)
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.iam.remove_user_from_group --group engineers --user alice
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
    {parsed, _args, _} = Helpers.parse_opts(argv, group: :string, user: :string)

    group_name = parsed[:group] || Mix.raise("--group is required")
    username = parsed[:user] || Mix.raise("--user is required")

    opts = Helpers.build_opts(parsed)

    group_name
    |> AwsSDK.IAM.remove_user_from_group(username, opts)
    |> Helpers.handle_result()
  end
end
