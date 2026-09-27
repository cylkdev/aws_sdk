defmodule Mix.Tasks.AwsSDK.AutoScaling.DescribeAutoScalingGroups do
  @shortdoc "Describes Auto Scaling groups"

  @moduledoc """
  Describes Auto Scaling groups.

  Maps directly to the AWS `DescribeAutoScalingGroups` API. The task does
  no client-side filtering or output reshaping; callers wanting to filter
  results (e.g. by `LifecycleState`) do so themselves with shell tooling
  or by calling `AwsSDK.AutoScaling.describe_auto_scaling_groups/1` from IEx.

  ## Usage

      mix aws_sdk.auto_scaling.describe_auto_scaling_groups [options]

  ## Options

    * `--name`         - ASG name (repeatable; maps to AWS `AutoScalingGroupNames.member.N`)
    * `--max-records`  - Max items per response
    * `--next-token`   - Pagination token
    * `--filter-<field>=<value>` - Client-side filter (repeatable). See below.
    * `--region`, `--profile`, `--access-key-id`, `--secret-access-key`, `--session-token`

  ## Client-side filtering

  Any `--filter-<field>=<value>` flag is applied to the parsed response after
  the API call. The walker narrows any list-of-maps where the field appears,
  so filters target the level of the response containing that field.
  Repeating the same filter flag OR-combines values; using different filter
  keys AND-combines them.

  ## Examples

      mix aws_sdk.auto_scaling.describe_auto_scaling_groups
      mix aws_sdk.auto_scaling.describe_auto_scaling_groups --name my-asg
      mix aws_sdk.auto_scaling.describe_auto_scaling_groups --name a --name b

      # Filter the nested `instances` list to just those in Pending:Wait
      mix aws_sdk.auto_scaling.describe_auto_scaling_groups --name my-asg \\
        --filter-lifecycle-state=Pending:Wait
  """

  use Mix.Task
  alias Mix.Tasks.AwsSDK.Helpers

  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {argv, filters} = Helpers.extract_filters(argv)

    {parsed, _args, _} =
      Helpers.parse_opts(argv,
        name: [:string, :keep],
        max_records: :integer,
        next_token: :string
      )

    names = Keyword.get_values(parsed, :name)

    call_opts =
      parsed
      |> Helpers.build_opts()
      |> add_names(names)
      |> Helpers.maybe_put(:max_records, parsed[:max_records])
      |> Helpers.maybe_put(:next_token, parsed[:next_token])

    call_opts
    |> AwsSDK.AutoScaling.describe_auto_scaling_groups()
    |> Helpers.apply_filters(filters)
    |> Helpers.handle_result()
  end

  defp add_names(opts, []), do: opts
  defp add_names(opts, names), do: Keyword.put(opts, :auto_scaling_group_names, names)
end
