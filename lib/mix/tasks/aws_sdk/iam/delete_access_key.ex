defmodule Mix.Tasks.AwsSDK.IAM.DeleteAccessKey do
  @shortdoc "Deletes an IAM access key"

  @moduledoc """
  Deletes an IAM access key for a user.

  ## Usage

      mix aws_sdk.iam.delete_access_key --key-id KEY_ID --user USER [options]

  ## Options

    * `--key-id` — Access key ID (required)
    * `--user` — User name (required)
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.iam.delete_access_key --key-id AKIAIOSFODNN7EXAMPLE --user alice
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
    {parsed, _args, _} = Helpers.parse_opts(argv, key_id: :string, user: :string)

    access_key_id = parsed[:key_id] || Mix.raise("--key-id is required")
    username = parsed[:user] || Mix.raise("--user is required")
    opts = Helpers.build_opts(parsed)

    access_key_id
    |> AwsSDK.IAM.delete_access_key(Keyword.put(opts, :user_name, username))
    |> Helpers.handle_result()
  end
end
