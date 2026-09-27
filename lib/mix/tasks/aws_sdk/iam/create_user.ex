defmodule Mix.Tasks.AwsSDK.IAM.CreateUser do
  @shortdoc "Creates an IAM user"

  @moduledoc """
  Creates an IAM user. Skips if a user with the same name already exists
  unless `--force` is given.

  ## Usage

      mix aws_sdk.iam.create_user --name NAME [options]

  ## Options

    * `--name` — User name (required)
    * `--path` — IAM path for the user (default: `/`)
    * `--force` / `-f` — Proceed even if user already exists
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.iam.create_user --name alice
      mix aws_sdk.iam.create_user --name alice --path /engineering/
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
    {parsed, _args, _} =
      Helpers.parse_opts(argv, name: :string, path: :string)

    username = parsed[:name] || Mix.raise("--name is required")

    opts =
      parsed
      |> Helpers.build_opts()
      |> Helpers.maybe_put(:path, parsed[:path])

    force = parsed[:force] || false

    Helpers.idempotent(
      username,
      fn -> AwsSDK.IAM.get_user(Keyword.put(opts, :user_name, username)) end,
      fn ->
        username
        |> AwsSDK.IAM.create_user(opts)
        |> Helpers.handle_result()
      end,
      force
    )
  end
end
