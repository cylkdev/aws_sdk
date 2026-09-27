defmodule Mix.Tasks.AwsSDK.AutoScaling.StartInstanceRefresh do
  @shortdoc "Starts an instance refresh for an Auto Scaling group"

  @moduledoc """
  Starts an instance refresh for an Auto Scaling group.

  Maps directly to the AWS `StartInstanceRefresh` API. The two JSON
  inputs accept any field the AWS API supports; the library does not
  validate or filter their contents.

  ## Usage

      mix aws_sdk.auto_scaling.start_instance_refresh --asg NAME [--strategy Rolling]
        [--preferences-json '{"MinHealthyPercentage":90}']
        [--desired-configuration-json '{"LaunchTemplate":{"LaunchTemplateName":"...","Version":"$Latest"}}']

  ## Options

    * `--asg`                        - ASG name (required)
    * `--strategy`                   - Refresh strategy (passes through to AWS `Strategy`)
    * `--preferences-json`           - JSON object passed verbatim to AWS `Preferences`
    * `--desired-configuration-json` - JSON object passed verbatim to AWS `DesiredConfiguration`
    * `--region`, `--profile`, `--access-key-id`, `--secret-access-key`, `--session-token`
  """

  use Mix.Task
  alias Mix.Tasks.AwsSDK.Helpers

  @requirements ["app.start"]

  @impl Mix.Task
  def run(argv) do
    {parsed, _args, _} =
      Helpers.parse_opts(argv,
        asg: :string,
        strategy: :string,
        preferences_json: :string,
        desired_configuration_json: :string
      )

    asg = parsed[:asg] || Mix.raise("--asg is required")

    preferences = parse_json_opt(parsed[:preferences_json])
    desired_configuration = parse_json_opt(parsed[:desired_configuration_json])

    call_opts =
      parsed
      |> Helpers.build_opts()
      |> Helpers.maybe_put(:strategy, parsed[:strategy])
      |> Helpers.maybe_put(:preferences, preferences)
      |> Helpers.maybe_put(:desired_configuration, desired_configuration)

    asg
    |> AwsSDK.AutoScaling.start_instance_refresh(call_opts)
    |> Helpers.handle_result()
  end

  defp parse_json_opt(nil), do: nil
  defp parse_json_opt(json), do: :json.decode(json)
end
