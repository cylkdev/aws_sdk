defmodule Mix.Tasks.AwsSDK.IAM.CreatePolicy do
  @shortdoc "Creates a managed IAM policy"

  @moduledoc """
  Creates a managed IAM policy. Skips if a policy with the same name already
  exists unless `--force` is given.

  ## Usage

      mix aws_sdk.iam.create_policy --name NAME --policy-document JSON [options]

  ## Options

    * `--name` — Policy name (required)
    * `--policy-document` — JSON policy document (required)
    * `--description` — Policy description
    * `--path` — IAM path (default: `/`)
    * `--force` / `-f` — Proceed even if a policy with this name already exists
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.iam.create_policy --name MyS3ReadPolicy \\
        --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetObject"],"Resource":"arn:aws:s3:::my-bucket/*"}]}'
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
        policy_document: :string,
        description: :string,
        path: :string
      )

    name = parsed[:name] || Mix.raise("--name is required")

    policy_json =
      parsed[:policy_document] || Mix.raise("--policy-document is required")

    policy_document =
      try do
        :json.decode(policy_json)
      rescue
        _ -> Mix.raise("--policy-document is not valid JSON")
      end

    opts =
      Helpers.build_opts(parsed)
      |> Helpers.maybe_put(:description, parsed[:description])
      |> Helpers.maybe_put(:path, parsed[:path])

    force = parsed[:force] || false

    Helpers.idempotent(
      name,
      fn -> find_policy(name, opts) end,
      fn ->
        name
        |> AwsSDK.IAM.create_policy(policy_document, opts)
        |> Helpers.handle_result()
      end,
      force
    )
  end

  defp find_policy(name, opts) do
    list_opts = Keyword.merge(opts, scope: "Local")

    case AwsSDK.IAM.list_policies(list_opts) do
      {:ok, %{policies: policies}} -> policy_lookup_result(policies, name)
      error -> error
    end
  end

  defp policy_lookup_result(policies, name) do
    if Enum.any?(policies, &(&1[:policy_name] === name)) do
      {:ok, %{}}
    else
      {:error, %{code: :not_found}}
    end
  end
end
