defmodule Mix.Tasks.AwsSDK.IAM.AttachPolicy do
  @shortdoc "Attaches a managed policy to a role, user, or group"

  @moduledoc """
  Attaches a managed IAM policy to a role, user, or group.
  Exactly one of `--to-role`, `--to-user`, or `--to-group` is required.

  ## Usage

      mix aws_sdk.iam.attach_policy --policy-arn ARN --to-role ROLE_NAME [options]
      mix aws_sdk.iam.attach_policy --policy-arn ARN --to-user USERNAME [options]
      mix aws_sdk.iam.attach_policy --policy-arn ARN --to-group GROUP_NAME [options]

  ## Options

    * `--policy-arn` — Policy ARN to attach (required)
    * `--to-role` — Role name to attach the policy to
    * `--to-user` — User name to attach the policy to
    * `--to-group` — Group name to attach the policy to
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.iam.attach_policy --policy-arn arn:aws:iam::aws:policy/AWSLambdaBasicExecutionRole --to-role MyLambdaRole
      mix aws_sdk.iam.attach_policy --policy-arn arn:aws:iam::123:policy/MyPolicy --to-user alice
      mix aws_sdk.iam.attach_policy --policy-arn arn:aws:iam::aws:policy/ReadOnlyAccess --to-group readers
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
        to_role: :string,
        to_user: :string,
        to_group: :string
      )

    policy_arn = parsed[:policy_arn] || Mix.raise("--policy-arn is required")

    opts = Helpers.build_opts(parsed)

    case {parsed[:to_role], parsed[:to_user], parsed[:to_group]} do
      {role, nil, nil} when is_binary(role) ->
        role
        |> AwsSDK.IAM.attach_role_policy(policy_arn, opts)
        |> Helpers.handle_result()

      {nil, user, nil} when is_binary(user) ->
        user
        |> AwsSDK.IAM.attach_user_policy(policy_arn, opts)
        |> Helpers.handle_result()

      {nil, nil, group} when is_binary(group) ->
        group
        |> AwsSDK.IAM.attach_group_policy(policy_arn, opts)
        |> Helpers.handle_result()

      _ ->
        Mix.raise("Exactly one of --to-role, --to-user, or --to-group is required")
    end
  end
end
