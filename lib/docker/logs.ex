defmodule Docker.Logs do
  require Logger

  @base_uri ""

  @doc """
  Get logs from a running Docker container.
  """
  def log(container_id, opts \\ %{})
  def log(container_id, opts) do
    url = "#{@base_uri}/containers/#{container_id}/logs?stderr=1&stdout=1&timestamps=1&follow=1&tail=10"
    %HTTPoison.AsyncResponse{id: id} = Docker.Client.stream(:get, url)
    handle_log(container_id)
  end


  defp handle_log(id) do
    receive do
      %HTTPoison.AsyncStatus{id: id, code: code} ->
        case code do
          200 -> handle_log(id)
          404 -> {:error, "Repository does not exist or no read access"}
          500 -> {:error, "Server error"}
          e ->
            Logger.warn("unknown: #{Kernel.inspect(e)}")
            {:error, "Server error"}
        end
      %HTTPoison.AsyncHeaders{id: id, headers: headers} ->
        Logger.info("AsyncHeaders: #{Kernel.inspect(headers)}")
        handle_log(id)
      %HTTPoison.AsyncChunk{id: id, chunk: chunk} ->
        Logger.info("#{Kernel.inspect(chunk)}")
        # << h :: size(8), l :: bitstring >> = chunk
        # IO.puts("> #{l}")
        handle_log(id)
      %HTTPoison.AsyncEnd{id: id} ->
        {:ok, "Image successfully loged"}
        handle_log(id)
      other ->
        Logger.info("How i'm suppose to handle this ?: #{Kernel.inspect(other)}")
    end
  end

  @doc """
  Log a Docker container_id and return the response in a stream.
  """
  def stream_log(container_id), do: stream_log(container_id, %{})
  def stream_log(container_id, opts) do
    stream = Stream.resource(
      fn -> start_log("#{@base_uri}/containers/#{container_id}/logs?stderr=1&stdout=1&timestamps=1&follow=1&tail=10") end,
      fn({id, status}) -> receive_log({id, status}) end,
      fn _ -> nil end
    )
    stream
  end

  defp start_log(url) do
    %HTTPoison.AsyncResponse{id: id} = Docker.Client.stream(:get, url)
    {id, :keepalive}
  end

  defp start_log(url, headers) do
    %HTTPoison.AsyncResponse{id: id} = Docker.Client.stream(:get, url, "", headers)
    {id, :keepalive}
  end

  defp parse_log_binary(logs) do
    messages = parse_log_part(logs)
    # IO.puts "‣ #{full_message}"

    for l <- messages do
      IO.puts "‣ #{l}"
    end

    # IO.inspect(messages)
  end

  defp parse_log_part(<<m_type::size(8), m_void::size(24), m_length::size(32), content::binary>>) do
    {s_content, remaining} = content |> String.split_at(m_length)
    [s_content | parse_log_part(remaining)]
  end

  defp parse_log_part(<<content::bitstring>>) do
    Logger.debug("end of the road: #{IO.puts(content)}")
    [content]
  end


  defp receive_log({_id, :kill}) do
    {:halt, nil}
  end
  defp receive_log({id, :keepalive}) do
    receive do
      %HTTPoison.AsyncStatus{id: ^id, code: code} ->
        IO.inspect code
        case code do
          200 -> {[{:ok, "Started loging"}], {id, :keepalive}}
          404 -> {[{:error, "Repository does not exist or no read access"}], {id, :kill}}
          500 -> {[{:error, "Server error"}], {id, :kill}}
          _ -> {[{:error, "Server error"}], {id, :kill}}
        end
      %HTTPoison.AsyncHeaders{id: ^id, headers: _headers} ->
        {[], {id, :keepalive}}
      %HTTPoison.AsyncChunk{id: ^id, chunk: chunk} ->
        IO.inspect(chunk, limit: :infinity)
        parse_log_binary(chunk)
        {:ok}
      %HTTPoison.AsyncEnd{id: ^id} ->
        IO.puts "asyncEnd"
        {[{:end, "Finished loging"}], {id, :kill}}
    end
  end

end
