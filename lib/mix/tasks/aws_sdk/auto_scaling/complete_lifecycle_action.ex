defmodule Mix.Tasks.AwsSDK.AutoScaling.CompleteLifecycleAction do
  @shortdoc "Completes a pending lifecycle action"

  @moduledoc """
  Completes a pending lifecycle action.

  Maps directly to the AWS `CompleteLifecycleAction` API.

  ## Usage

      mix aws_sdk.auto_scaling.complete_lifecycle_action --asg NAME \\
        --hook-name HOOK --result CONTINUE|ABANDON \\
        (--instance-id ID | --token TOKEN)

  ## Options

    * `--asg`         - Auto Scaling group name (required)
    * `--hook-name`   - Lifecycle hook name (required)
    * `--result`      - `CONTINUE` or `ABANDON` (required)
    * `--instance-id` - Instance ID
    * `--token`       - Lifecycle action token (alternative to `--instance-id`)
    * `--region`, `--profile`, `--access-key-id`, `--secret-access-key`, `--session-token`

  Either `--instance-id` or `--token` must be provided.
  """

  use Mix.Task
  alias Mix.Tasks.AwsSDK.Helpers

  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {parsed, _args, _} =
      Helpers.parse_opts(argv,
        asg: :string,
        hook_name: :string,
        instance_id: :string,
        token: :string,
        result: :string
      )

    asg = parsed[:asg] || Mix.raise("--asg is required")
    hook_name = parsed[:hook_name] || Mix.raise("--hook-name is required")
    result = parsed[:result] || Mix.raise("--result is required")

    if !parsed[:instance_id] and !parsed[:token] do
      Mix.raise("either --instance-id or --token is required")
    end

    call_opts =
      parsed
      |> Helpers.build_opts()
      |> Helpers.maybe_put(:instance_id, parsed[:instance_id])
      |> Helpers.maybe_put(:lifecycle_action_token, parsed[:token])

    hook_name
    |> AwsSDK.AutoScaling.complete_lifecycle_action(asg, result, call_opts)
    |> Helpers.handle_result()
  end
end
