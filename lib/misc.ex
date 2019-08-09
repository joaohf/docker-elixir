defmodule Docker.Misc do
  @moduledoc """
  Docker misc methods.
  """
  require Logger

  @doc """
  Display system-wide information.
  """
  def info do
    "/info"
    |> Docker.Client.get()
    |> decode_system_response
  end

  @doc """
  Show the docker version information.
  """
  def version do
    "/version"
    |> Docker.Client.get()
    |> decode_system_response
  end

  defp decode_system_response(%HTTPoison.Response{body: body, status_code: status_code}) do
    Logger.debug(fn -> "Decoding Docker API response: #{inspect(body)}" end)

    case Poison.decode(body) do
      {:ok, dict} ->
        case status_code do
          200 -> {:ok, dict}
          500 -> {:error, "Server error"}
          _ -> {:error, "Unknow error"}
        end

      {:error, message} ->
        {:error, message}

      _ ->
        {:error, "Unknow error"}
    end
  end

  @doc """
  Ping the docker server.
  """
  def ping do
    "/_ping"
    |> Docker.Client.get()
    |> decode_ping_response
  end

  defp decode_ping_response(%HTTPoison.Response{body: body, status_code: status_code}) do
    case status_code do
      200 -> {:ok, body}
      500 -> {:error, "Server error"}
    end
  end

  @doc """
  Monitor Docker's events since given timestamp.
  """
  def events(since), do: Docker.Client.get("/events?since=#{since}")

  @doc """
  Monitor Docker's events as stream. LEGACY.
  """
  def events_stream, do: Docker.Client.stream(:get, "/events")

  def events_stream(filter) do
    json = filter |> Poison.encode!()
    Docker.Client.stream(:get, "/events?filters=#{json}")
  end

  @doc """
  Return real-time events from server as a stream.
  """
  def stream_events do
    stream =
      Stream.resource(
        fn -> start_streaming_events("/events") end,
        fn {id, status} -> receive_events({id, status}) end,
        fn id -> stop_streaming_events(id) end
      )

    stream
  end

  defp start_streaming_events(url) do
    %HTTPoison.AsyncResponse{id: id} = Docker.Client.stream(:get, url)
    {id, :keepalive}
  end

  defp receive_events({id, :kill}) do
    {:halt, id}
  end

  defp receive_events({id, :keepalive}) do
    receive do
      %HTTPoison.AsyncStatus{id: ^id, code: code} ->
        case code do
          200 -> {[{:ok, "Started streaming events"}], {id, :keepalive}}
          400 -> {[{:error, "Bad parameter"}], {id, :kill}}
          500 -> {[{:error, "Server error"}], {id, :kill}}
          _ -> {[{:error, "Unknow error"}], {id, :kill}}
        end

      %HTTPoison.AsyncHeaders{id: ^id, headers: _headers} ->
        {[], {id, :keepalive}}

      %HTTPoison.AsyncChunk{id: ^id, chunk: chunk} ->
        case Poison.decode(chunk) do
          {:ok, event} ->
            {[{:event, event}], {id, :keepalive}}

          _ ->
            {[], {id, :keepalive}}
        end

      %HTTPoison.AsyncEnd{id: ^id} ->
        {[{:end, "Finished streaming"}], {id, :kill}}
    end
  end

  defp stop_streaming_events(id) do
    :hackney.stop_async(id)
  end

  def parse_stream_log(<<header::bytes-size(8), payload::bitstring>>) do
    {_, s} = stream_header(header)
    binary_part(payload, 0, s)
  end

  defp stream_header(
         <<stream_type::bytes-size(1), 0, 0, 0,
           payload_size::integer-big-unsigned-unit(32)-size(1)>>
       ) do
    {stream_type(stream_type), payload_size}
  end

  defp stream_type(<<0>>), do: "stdin"
  defp stream_type(<<1>>), do: "stdout"
  defp stream_type(<<2>>), do: "stderr"
end
