defmodule Mix.Tasks.AwsSDK.IdentityCenter.CreateAccountAssignment do
  @shortdoc "Assigns a permission set to a principal in an AWS account"

  @moduledoc """
  Creates an account assignment that grants a user or group access to an
  AWS account via a permission set.

  ## Usage

      mix aws_sdk.identity_center.create_account_assignment --instance-arn ARN [options]

  ## Options

    * `--instance-arn` — Identity Center instance ARN (required)
    * `--account-id` — AWS account ID to grant access to (required)
    * `--permission-set-arn` — ARN of the permission set (required)
    * `--principal-type` — `USER` or `GROUP` (required)
    * `--principal-id` — User or group ID from the identity store (required)
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.identity_center.create_account_assignment \\
        --instance-arn arn:aws:sso:::instance/ssoins-1 \\
        --account-id 123456789012 \\
        --permission-set-arn arn:aws:sso:::permissionSet/ssoins-1/ps-123 \\
        --principal-type USER \\
        --principal-id abc123-user-id
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
        account_id: :string,
        permission_set_arn: :string,
        principal_type: :string,
        principal_id: :string
      )

    instance_arn = parsed[:instance_arn] || Mix.raise("--instance-arn is required")

    account_id = parsed[:account_id] || Mix.raise("--account-id is required")

    permission_set_arn =
      parsed[:permission_set_arn] || Mix.raise("--permission-set-arn is required")

    principal_type = parsed[:principal_type] || Mix.raise("--principal-type is required")
    principal_id = parsed[:principal_id] || Mix.raise("--principal-id is required")

    opts = Helpers.build_opts(parsed)

    assignment = %{
      target_id: account_id,
      target_type: "AWS_ACCOUNT",
      permission_set_arn: permission_set_arn,
      principal_type: principal_type,
      principal_id: principal_id
    }

    instance_arn
    |> AwsSDK.IdentityCenter.create_account_assignment(assignment, opts)
    |> Helpers.handle_result()
  end
end
