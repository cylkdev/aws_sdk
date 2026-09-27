defmodule Mix.Tasks.AwsSDK.IAM.CreateRole do
  @shortdoc "Creates an IAM role with a trust policy"

  @moduledoc """
  Creates an IAM role. Skips if a role with the same name already exists
  unless `--force` is given.

  The trust policy defines which principals can assume the role (e.g. Lambda,
  EC2, another AWS account). Pass it as a JSON string via `--trust-policy`.

  ## Usage

      mix aws_sdk.iam.create_role --name NAME --trust-policy JSON [options]

  ## Options

    * `--name` — Role name (required)
    * `--trust-policy` — JSON trust policy document (required)
    * `--description` — Role description
    * `--path` — IAM path (default: `/`)
    * `--max-session-duration` — Max session duration in seconds (default: 3600)
    * `--force` / `-f` — Proceed even if role already exists
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.iam.create_role --name MyLambdaRole \\
        --trust-policy '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"lambda.amazonaws.com"},"Action":"sts:AssumeRole"}]}'

      mix aws_sdk.iam.create_role --name MyEC2Role \\
        --trust-policy '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \\
        --description "Role for EC2 instances"
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
        name: :string,
        trust_policy: :string,
        description: :string,
        path: :string,
        max_session_duration: :integer
      )

    name = parsed[:name] || Mix.raise("--name is required")

    trust_policy_json =
      parsed[:trust_policy] || Mix.raise("--trust-policy is required")

    trust_policy =
      try do
        :json.decode(trust_policy_json)
      rescue
        _ -> Mix.raise("--trust-policy is not valid JSON")
      end

    opts =
      Helpers.build_opts(parsed)
      |> Helpers.maybe_put(:description, parsed[:description])
      |> Helpers.maybe_put(:path, parsed[:path])
      |> Helpers.maybe_put(:max_session_duration, parsed[:max_session_duration])

    force = parsed[:force] || false

    Helpers.idempotent(
      name,
      fn -> AwsSDK.IAM.get_role(name, opts) end,
      fn ->
        Helpers.handle_result(AwsSDK.IAM.create_role(name, trust_policy, opts))
      end,
      force
    )
  end
end
