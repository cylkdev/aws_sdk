defmodule AwsSDK.Credentials.Providers.CredentialProcess do
  @moduledoc """
  Runs the profile's `credential_process` command and parses its JSON
  output (delegated to `AwsSDK.Credentials.ProcessCreds`).

  The expected output shape is documented at
  https://docs.aws.amazon.com/cli/latest/topic/config-vars.html#sourcing-credentials-from-external-processes.
  """

  alias AwsSDK.Credentials.ProcessCreds
  alias AwsSDK.Credentials.Profile

  @doc false
  def resolve(opts) do
    profile_name = opts[:profile] || Profile.default()

    with profile when is_map(profile) <- Profile.load(profile_name, opts),
         command when is_binary(command) <- profile["credential_process"] do
      ProcessCreds.run(command, :credential_process)
    else
      _ -> :skip
    end
  end
end
