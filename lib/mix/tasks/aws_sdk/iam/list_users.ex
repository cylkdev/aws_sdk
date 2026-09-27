defmodule Mix.Tasks.AwsSDK.IAM.ListUsers do
  @shortdoc "Lists IAM users"

  @moduledoc """
  Lists IAM users, optionally filtered by path prefix.

  ## Usage

      mix aws_sdk.iam.list_users [options]

  ## Options

    * `--path-prefix` — Filter users whose path begins with this string
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.iam.list_users
      mix aws_sdk.iam.list_users --path-prefix /engineering/
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
    {parsed, _args, _} = Helpers.parse_opts(argv, path_prefix: :string)

    opts =
      parsed
      |> Helpers.build_opts()
      |> Helpers.maybe_put(:path_prefix, parsed[:path_prefix])

    opts
    |> AwsSDK.IAM.list_users()
    |> Helpers.handle_result()
  end
end
