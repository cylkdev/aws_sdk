defmodule Mix.Tasks.AwsSDK.IAM.CreateGroup do
  @shortdoc "Creates an IAM group"

  @moduledoc """
  Creates an IAM group. Skips if a group with the same name already exists
  unless `--force` is given.

  ## Usage

      mix aws_sdk.iam.create_group --name NAME [options]

  ## Options

    * `--name` — Group name (required)
    * `--path` — IAM path for the group (default: `/`)
    * `--force` / `-f` — Proceed even if group already exists
    * `--region` / `-r` — AWS region (default: config or `AwsSDK.Config.region/0`)

  ## Examples

      mix aws_sdk.iam.create_group --name engineers
      mix aws_sdk.iam.create_group --name engineers --path /teams/
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
    {parsed, _args, _} = Helpers.parse_opts(argv, name: :string, path: :string)

    name = parsed[:name] || Mix.raise("--name is required")

    opts =
      parsed
      |> Helpers.build_opts()
      |> Helpers.maybe_put(:path, parsed[:path])

    force = parsed[:force] || false

    Helpers.idempotent(
      name,
      fn -> find_group(AwsSDK.IAM.list_groups(opts), name) end,
      fn ->
        name
        |> AwsSDK.IAM.create_group(opts)
        |> Helpers.handle_result()
      end,
      force
    )
  end

  defp find_group({:ok, %{groups: groups}}, name) do
    if Enum.any?(groups, &(&1[:group_name] === name)) do
      {:ok, %{}}
    else
      {:error, %{code: :not_found}}
    end
  end

  defp find_group({:error, _} = error, _), do: error
end
