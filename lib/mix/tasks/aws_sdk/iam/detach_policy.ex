defmodule Mix.Tasks.AwsSDK.IAM.DetachPolicy do
  @shortdoc "Detaches a managed policy from a role, user, or group"

  @moduledoc """
  Detaches a managed IAM policy from a role, user, or group.
  Exactly one of `--from-role`, `--from-user`, or `--from-group` is required.

  ## Usage

      mix aws_sdk.iam.detach_policy --policy-arn ARN --from-role ROLE_NAME [options]
      mix aws_sdk.iam.detach_policy --policy-arn ARN --from-user USERNAME [options]
      mix aws_sdk.iam.detach_policy --policy-arn ARN --from-group GROUP_NAME [options]

  ## Options

    * `--policy-arn` — Policy ARN to detach (required)
    * `--from-role` — Role name to detach the policy from
    * `--from-user` — User name to detach the policy from
    * `--from-group` — Group name to detach the policy from
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.iam.detach_policy --policy-arn arn:aws:iam::aws:policy/AWSLambdaBasicExecutionRole --from-role MyLambdaRole
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
        policy_arn: :string,
        from_role: :string,
        from_user: :string,
        from_group: :string
      )

    policy_arn = parsed[:policy_arn] || Mix.raise("--policy-arn is required")

    opts = Helpers.build_opts(parsed)

    case {parsed[:from_role], parsed[:from_user], parsed[:from_group]} do
      {role, nil, nil} when is_binary(role) ->
        role
        |> AwsSDK.IAM.detach_role_policy(policy_arn, opts)
        |> Helpers.handle_result()

      {nil, user, nil} when is_binary(user) ->
        user
        |> AwsSDK.IAM.detach_user_policy(policy_arn, opts)
        |> Helpers.handle_result()

      {nil, nil, group} when is_binary(group) ->
        group
        |> AwsSDK.IAM.detach_group_policy(policy_arn, opts)
        |> Helpers.handle_result()

      _ ->
        Mix.raise("Exactly one of --from-role, --from-user, or --from-group is required")
    end
  end
end
