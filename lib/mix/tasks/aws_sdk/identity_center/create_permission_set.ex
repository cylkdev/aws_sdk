defmodule Mix.Tasks.AwsSDK.IdentityCenter.CreatePermissionSet do
  @shortdoc "Creates an Identity Center permission set"

  @moduledoc """
  Creates a permission set in an IAM Identity Center instance. Skips if a
  permission set with the same name already exists unless `--force` is given.

  ## Usage

      mix aws_sdk.identity_center.create_permission_set --instance-arn ARN --name NAME [options]

  ## Options

    * `--instance-arn` — Identity Center instance ARN (required)
    * `--name` — Permission set name (required)
    * `--description` — Description for the permission set
    * `--session-duration` — ISO 8601 session duration (e.g. `PT8H` for 8 hours)
    * `--force` / `-f` — Proceed even if it already exists
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.identity_center.create_permission_set --instance-arn arn:aws:sso:::instance/ssoins-1 --name AdministratorAccess
      mix aws_sdk.identity_center.create_permission_set --instance-arn arn:aws:sso:::instance/ssoins-1 --name ReadOnlyAccess --session-duration PT4H
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
      Helpers.parse_opts(argv,
        instance_arn: :string,
        name: :string,
        description: :string,
        session_duration: :string
      )

    instance_arn = parsed[:instance_arn] || Mix.raise("--instance-arn is required")
    name = parsed[:name] || Mix.raise("--name is required")

    opts =
      Helpers.build_opts(parsed)
      |> Helpers.maybe_put(:description, parsed[:description])
      |> Helpers.maybe_put(:session_duration, parsed[:session_duration])

    force = parsed[:force] || false

    Helpers.idempotent(
      name,
      fn ->
        case AwsSDK.IdentityCenter.list_permission_sets(instance_arn, opts) do
          {:ok, %{permission_sets: _}} -> {:error, %{code: :not_found}}
          error -> error
        end
      end,
      fn ->
        instance_arn
        |> AwsSDK.IdentityCenter.create_permission_set(name, opts)
        |> Helpers.handle_result()
      end,
      force
    )
  end
end
