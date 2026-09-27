defmodule Mix.Tasks.AwsSDK.IdentityCenter.ListPermissionSets do
  @shortdoc "Lists permission sets in an Identity Center instance"

  @moduledoc """
  Lists permission set ARNs in an IAM Identity Center instance.

  ## Usage

      mix aws_sdk.identity_center.list_permission_sets --instance-arn ARN [options]

  ## Options

    * `--instance-arn` — Identity Center instance ARN (required)
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.identity_center.list_permission_sets --instance-arn arn:aws:sso:::instance/ssoins-1
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
    {parsed, _args, _} = Helpers.parse_opts(argv, instance_arn: :string)

    instance_arn = parsed[:instance_arn] || Mix.raise("--instance-arn is required")

    opts = Helpers.build_opts(parsed)

    instance_arn
    |> AwsSDK.IdentityCenter.list_permission_sets(opts)
    |> Helpers.handle_result()
  end
end
