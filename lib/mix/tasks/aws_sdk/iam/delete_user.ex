defmodule Mix.Tasks.AwsSDK.IAM.DeleteUser do
  @shortdoc "Deletes an IAM user"

  @moduledoc """
  Deletes an IAM user.

  ## Usage

      mix aws_sdk.iam.delete_user --name NAME [options]

  ## Options

    * `--name` — User name (required)
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.iam.delete_user --name alice
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
    {parsed, _args, _} = Helpers.parse_opts(argv, name: :string)

    username = parsed[:name] || Mix.raise("--name is required")
    opts = Helpers.build_opts(parsed)

    username
    |> AwsSDK.IAM.delete_user(opts)
    |> Helpers.handle_result()
  end
end
