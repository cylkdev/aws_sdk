defmodule Mix.Tasks.AwsSDK.IAM.DeletePolicy do
  @shortdoc "Deletes a managed IAM policy"

  @moduledoc """
  Deletes a managed IAM policy by ARN.

  Note: All policy attachments must be removed before the policy can be deleted.

  ## Usage

      mix aws_sdk.iam.delete_policy --arn ARN [options]

  ## Options

    * `--arn` — Policy ARN (required)
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.iam.delete_policy --arn arn:aws:iam::123456789012:policy/MyS3ReadPolicy
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
    {parsed, _args, _} = Helpers.parse_opts(argv, arn: :string)

    policy_arn = parsed[:arn] || Mix.raise("--arn is required")

    opts = Helpers.build_opts(parsed)

    policy_arn
    |> AwsSDK.IAM.delete_policy(opts)
    |> Helpers.handle_result()
  end
end
