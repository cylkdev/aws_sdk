defmodule Mix.Tasks.AwsSDK.IdentityCenter.DetachManagedPolicy do
  @shortdoc "Detaches a managed policy from a permission set"

  @moduledoc """
  Detaches an AWS managed policy from an Identity Center permission set.

  ## Usage

      mix aws_sdk.identity_center.detach_managed_policy --instance-arn ARN --permission-set-arn ARN --policy-arn ARN [options]

  ## Options

    * `--instance-arn` — Identity Center instance ARN (required)
    * `--permission-set-arn` — Permission set ARN (required)
    * `--policy-arn` — Managed policy ARN to detach (required)
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.identity_center.detach_managed_policy \\
        --instance-arn arn:aws:sso:::instance/ssoins-1 \\
        --permission-set-arn arn:aws:sso:::permissionSet/ssoins-1/ps-123 \\
        --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
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
        permission_set_arn: :string,
        policy_arn: :string
      )

    instance_arn = parsed[:instance_arn] || Mix.raise("--instance-arn is required")

    permission_set_arn =
      parsed[:permission_set_arn] || Mix.raise("--permission-set-arn is required")

    managed_policy_arn = parsed[:policy_arn] || Mix.raise("--policy-arn is required")

    opts = Helpers.build_opts(parsed)

    instance_arn
    |> AwsSDK.IdentityCenter.detach_managed_policy_from_permission_set(
      permission_set_arn,
      managed_policy_arn,
      opts
    )
    |> Helpers.handle_result()
  end
end
