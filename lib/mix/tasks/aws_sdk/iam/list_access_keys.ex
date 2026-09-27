defmodule Mix.Tasks.AwsSDK.IAM.ListAccessKeys do
  @shortdoc "Lists access keys for an IAM user"

  @moduledoc """
  Lists access key metadata for an IAM user.

  Note: The `secret_access_key` is not returned by this operation.

  ## Usage

      mix aws_sdk.iam.list_access_keys --user USER [options]

  ## Options

    * `--user` — User name (required)
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.iam.list_access_keys --user alice
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
    {parsed, _args, _} = Helpers.parse_opts(argv, user: :string)

    username = parsed[:user] || Mix.raise("--user is required")
    opts = Helpers.build_opts(parsed)

    opts
    |> Keyword.put(:user_name, username)
    |> AwsSDK.IAM.list_access_keys()
    |> Helpers.handle_result()
  end
end
