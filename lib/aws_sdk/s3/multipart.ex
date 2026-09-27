defmodule AwsSDK.S3.Multipart do
  @moduledoc """
  Helper utilities for multipart S3 operations.

  Provides functions for computing byte ranges used during multipart copy
  operations. A "content byte stream" is a lazy enumerable of
  `{start_byte, end_byte}` tuples that partition a content range into
  fixed-size chunks.
  """

  @doc """
  Returns a stream of `{start_byte, end_byte}` tuples that partition the range
  from `start_index` to `content_length - 1` into chunks of `chunk_size` bytes.

  The last chunk may be smaller than `chunk_size` if the content length is not
  evenly divisible.

  ## Arguments

    - start_index: The byte offset to start from (typically 0).
    - content_length: The total number of bytes in the content.
    - chunk_size: The size of each chunk in bytes.

  ## Examples

      iex> AwsSDK.S3.Multipart.content_byte_stream(0, 200, 64) |> Enum.to_list()
      [{0, 63}, {64, 127}, {128, 191}, {192, 199}]

      iex> AwsSDK.S3.Multipart.content_byte_stream(0, 64, 64) |> Enum.to_list()
      [{0, 63}]

  ## Examples

      AwsSDK.S3.Multipart.content_byte_stream(0, 12_000_000, 5_242_880) |> Enum.to_list()
      #=> [{0, 5_242_879}, {5_242_880, 10_485_759}, {10_485_760, 11_999_999}]

  Each tuple is an inclusive `{first_byte, last_byte}` range, ready to
  format as an HTTP `Range` header. The final range is short whenever the
  content does not divide evenly by the chunk size.
  """
  @spec content_byte_stream(
          start_index :: non_neg_integer(),
          content_length :: pos_integer(),
          chunk_size :: pos_integer()
        ) :: Enumerable.t()
  def content_byte_stream(start_index, content_length, chunk_size) do
    Stream.unfold(start_index, fn
      current when current >= content_length ->
        nil

      current ->
        end_byte = min(current + chunk_size - 1, content_length - 1)
        {{current, end_byte}, end_byte + 1}
    end)
  end
end
