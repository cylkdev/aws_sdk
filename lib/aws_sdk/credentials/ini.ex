defmodule AwsSDK.Credentials.INI do
  @moduledoc """
  Minimal INI parser for AWS credential and config files.

  Returns every `[section]` found in the file as a map of string keys to
  string values. Section headers and keys are trimmed; inline `#`
  comments are stripped.
  """

  @type sections :: %{optional(String.t()) => %{optional(String.t()) => String.t()}}

  @doc """
  Reads and parses the INI file at `path`.

  Returns `{:ok, sections}` when the file exists and parses cleanly,
  `{:error, :enoent}` when the file is missing, or `{:error, posix}`
  for other read errors.

  ## Examples

      AwsSDK.Credentials.INI.read("/Users/you/.aws/config")
      #=> %{
      #=>   "default" => %{"region" => "us-east-1"},
      #=>   "profile dev" => %{"role_arn" => "arn:aws:iam::123456789012:role/dev"}
      #=> }

      AwsSDK.Credentials.INI.read("/no/such/file")
      #=> %{}

  A missing or unreadable file yields an empty map rather than raising, so a
  machine with no `~/.aws` still resolves credentials from other sources.
  """
  @spec read(Path.t()) :: {:ok, sections} | {:error, File.posix()}
  def read(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, parse(contents)}
      {:error, _} = err -> err
    end
  end

  @doc """
  Parses a full INI document into a `%{section => %{key => value}}` map.

  ## Examples

      AwsSDK.Credentials.INI.parse("[default]\nregion = us-east-1\n\n[profile dev]\nrole_arn = arn:aws:iam::123456789012:role/dev\n")
      #=> %{
      #=>   "default" => %{"region" => "us-east-1"},
      #=>   "profile dev" => %{"role_arn" => "arn:aws:iam::123456789012:role/dev"}
      #=> }

  Section names are kept verbatim, so a config-file profile stays
  `"profile dev"` rather than being rewritten to `"dev"`.

  A `#` only starts a comment at the beginning of a line or after
  whitespace, so values may contain one:

      AwsSDK.Credentials.INI.parse("[p]\nsecret = abc#def\n")
      #=> %{"p" => %{"secret" => "abc#def"}}
  """
  @spec parse(String.t()) :: sections
  def parse(contents) when is_binary(contents) do
    contents
    |> String.split(~r/\r?\n/)
    |> Enum.reduce({nil, %{}}, &reduce_line/2)
    |> elem(1)
  end

  defp reduce_line(raw_line, {section, acc}) do
    line = raw_line |> strip_comment() |> String.trim()

    cond do
      line === "" ->
        {section, acc}

      String.starts_with?(line, "[") and String.ends_with?(line, "]") ->
        new_section = line |> String.slice(1..-2//1) |> String.trim()
        {new_section, Map.put_new(acc, new_section, %{})}

      section !== nil and String.contains?(line, "=") ->
        [k, v] = String.split(line, "=", parts: 2)

        entry =
          Map.update(
            acc,
            section,
            %{String.trim(k) => String.trim(v)},
            &Map.put(&1, String.trim(k), String.trim(v))
          )

        {section, entry}

      true ->
        {section, acc}
    end
  end

  # The AWS CLI treats `#` as a comment only at the start of a line or after
  # whitespace. Splitting on any `#` truncated legitimate values -- a URL
  # fragment, or a secret that happens to contain one.
  defp strip_comment(line) do
    case Regex.run(~r/(^|\s)#/, line, return: :index) do
      nil -> line
      [{start, len} | _] -> String.slice(line, 0, start + len - 1)
    end
  end
end
