defmodule Mix.Tasks.AwsSDK.SSO.Login do
  @shortdoc "Runs the AWS SSO device-code login flow for a profile"

  @moduledoc """
  Runs the AWS SSO (Identity Center) OIDC device-code flow for the
  given profile, writing the refreshed token cache under
  `~/.aws/sso/cache/`.

  ## Usage

      mix aws_sdk.sso.login --profile dev

  ## Switches

    * `--profile` — profile name in `~/.aws/config`; defaults to
      `$AWS_PROFILE` or `default`.
  """

  use Mix.Task

  alias AwsSDK.Credentials.Profile
  alias AwsSDK.Credentials.SSO.Login

  @switches [profile: :string]

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
    {opts, _args, _invalid} = OptionParser.parse(argv, strict: @switches)
    profile = opts[:profile] || Profile.default()

    case Login.run(profile, skip_browser_open: false) do
      {:ok, _cache} ->
        Mix.shell().info("SSO login complete for profile '#{profile}'.")

      {:error, reason} ->
        Mix.raise("SSO login failed: #{inspect(reason)}")
    end
  end
end
