defmodule Mix.Tasks.AwsSDK.AutoScaling.DescribeInstanceRefreshes do
  @shortdoc "Describes instance refreshes for an Auto Scaling group"

  @moduledoc """
  Describes instance refreshes for an Auto Scaling group.

  Maps directly to the AWS `DescribeInstanceRefreshes` API.

  ## Usage

      mix aws_sdk.auto_scaling.describe_instance_refreshes --asg NAME [options]

  ## Options

    * `--asg`          - Auto Scaling group name (required)
    * `--max-records`  - Max items per response
    * `--next-token`   - Pagination token
    * `--filter-<field>=<value>` - Client-side filter on the response (repeatable)
    * `--region`, `--profile`, `--access-key-id`, `--secret-access-key`, `--session-token`

  ## Examples

      mix aws_sdk.auto_scaling.describe_instance_refreshes --asg my-asg
      mix aws_sdk.auto_scaling.describe_instance_refreshes --asg my-asg --filter-status=InProgress
  """

  use Mix.Task
  alias Mix.Tasks.AwsSDK.Helpers

  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {argv, filters} = Helpers.extract_filters(argv)

    {parsed, _args, _} =
      Helpers.parse_opts(argv,
        asg: :string,
        max_records: :integer,
        next_token: :string
      )

    asg = parsed[:asg] || Mix.raise("--asg is required")

    call_opts =
      parsed
      |> Helpers.build_opts()
      |> Helpers.maybe_put(:max_records, parsed[:max_records])
      |> Helpers.maybe_put(:next_token, parsed[:next_token])

    asg
    |> AwsSDK.AutoScaling.describe_instance_refreshes(call_opts)
    |> Helpers.apply_filters(filters)
    |> Helpers.handle_result()
  end
end
