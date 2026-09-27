defmodule AwsSDK.Query do
  @moduledoc """
  Flattens a nested map into AWS Query-protocol form parameters.

  Two list encodings exist because AWS defines two protocols:

    * `:query` — `Key.member.N`, used by IAM, STS, Auto Scaling and ELBv2
    * `:ec2` — `Key.N`, used only by EC2

  This is AWS's distinction (botocore `"protocol": "query"` vs
  `"protocol": "ec2"`), not a choice this library makes.

      iex> AwsSDK.Query.encode(%{"Names" => ["a", "b"]}, :query)
      %{"Names.member.1" => "a", "Names.member.2" => "b"}

      iex> AwsSDK.Query.encode(%{"InstanceId" => ["i-1"]}, :ec2)
      %{"InstanceId.1" => "i-1"}

  `nil` and `[]` are dropped. Atom keys are PascalCased; binary keys are
  passed through untouched, which is how callers spell names Recase would
  get wrong (`DNSName`).

  ## Examples

      AwsSDK.Query.encode(%{name: "web", filters: [%{name: "vpc-id", values: ["vpc-1"]}]}, :query)
      #=> %{
      #=>   "Name" => "web",
      #=>   "Filters.member.1.Name" => "vpc-id",
      #=>   "Filters.member.1.Values.member.1" => "vpc-1"
      #=> }

  EC2 indexes lists without the `member` segment:

      AwsSDK.Query.encode(%{instance_id: ["i-1", "i-2"]}, :ec2)
      #=> %{"InstanceId.1" => "i-1", "InstanceId.2" => "i-2"}

  Atom keys are PascalCased; binary keys pass through untouched. `nil` and
  `[]` values are dropped rather than sent as empty parameters.
  """

  @type style :: :query | :ec2

  @spec encode(map, style) :: %{optional(String.t()) => String.t()}
  def encode(input, style \\ :query) when is_map(input) do
    Enum.reduce(input, %{}, fn {k, v}, acc -> put(acc, pascal(k), v, style) end)
  end

  defp put(acc, _key, nil, _style), do: acc
  defp put(acc, _key, [], _style), do: acc

  defp put(acc, key, list, style) when is_list(list) do
    list
    |> Enum.with_index(1)
    |> Enum.reduce(acc, fn {item, idx}, inner ->
      put(inner, "#{key}#{index_separator(style)}#{idx}", item, style)
    end)
  end

  defp put(acc, key, map, style) when is_map(map) do
    Enum.reduce(map, acc, fn {sub_k, sub_v}, inner ->
      put(inner, "#{key}.#{pascal(sub_k)}", sub_v, style)
    end)
  end

  defp put(acc, key, value, _style) when is_boolean(value),
    do: Map.put(acc, key, to_string(value))

  defp put(acc, key, value, _style) when is_atom(value),
    do: Map.put(acc, key, Atom.to_string(value))

  defp put(acc, key, value, _style), do: Map.put(acc, key, to_string(value))

  defp index_separator(:query), do: ".member."
  defp index_separator(:ec2), do: "."

  defp pascal(key) when is_binary(key), do: key
  defp pascal(key) when is_atom(key), do: key |> Atom.to_string() |> Recase.to_pascal()
end
