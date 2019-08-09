defmodule Docker.Containers do
  @moduledoc """
  Docker containers methods.
  """
  require Logger
  @base_uri "/containers"

  @doc """
  List all running containers.
  """
  def list_running do
    list(%{all: false})
  end

  @doc """
  List containers (all existing containers by default).
  """
  def list(opts \\ %{all: true}) do
    Docker.Client.add_query_params("#{@base_uri}/json", opts)
    |> Docker.Client.get()
    |> decode_list_response
  end

  defp decode_list_response(%HTTPoison.Response{body: body, status_code: status_code}) do
    Logger.debug(fn -> "Decoding Docker API response: #{Kernel.inspect(body)}" end)

    case Poison.decode(body) do
      {:ok, dict} ->
        case status_code do
          200 -> {:ok, dict}
          400 -> {:error, "Bad parameter"}
          500 -> {:error, "Server error"}
          code -> {:error, "Unknown code: #{code}"}
        end

      {:error, message} ->
        {:error, message}
    end
  end

  @doc """
  Inspect a container by ID.
  """
  def inspect(id) do
    "#{@base_uri}/#{id}/json"
    |> Docker.Client.get()
    |> decode_inspect_response
  end

  defp decode_inspect_response(%HTTPoison.Response{body: body, status_code: status_code}) do
    Logger.debug(fn -> "Decoding Docker API response: #{Kernel.inspect(body)}" end)

    case Poison.decode(body) do
      {:ok, dict} ->
        case status_code do
          200 ->
            {:ok, dict}

          404 ->
            {:error, "No such container"}

          500 ->
            Logger.error(Kernel.inspect(body))
            {:error, "Server error"}

          code ->
            {:error, "Unknown code: #{code}"}
        end

      {:error, message} ->
        {:error, message}
    end
  end

  @doc """
  Create a container from an existing image.
  """
  def create(conf) do
    "#{@base_uri}/create"
    |> Docker.Client.post(conf)
    |> decode_create_response
  end

  def create(conf, name) do
    "#{@base_uri}/create?name=#{name}"
    |> Docker.Client.post(conf)
    |> decode_create_response
  end

  defp decode_create_response(%HTTPoison.Response{body: body, status_code: status_code}) do
    with 201 <- status_code,
         {:ok, res} <- Poison.decode(body) do
      {:ok, res}
    else
      400 -> {:error, "Bad parameter"}
      404 -> {:error, "No such container"}
      406 -> {:error, "Impossible to attach"}
      409 -> {:error, "Conflict"}
      500 -> {:error, "Server Error"}
      _ -> {:error, "Unknown error #{Kernel.inspect(body)}"}
    end
  end

  @doc """
  Remove a container. Assumes the container is already stopped.
  """
  def remove(id) do
    "#{@base_uri}/#{id}"
    |> Docker.Client.delete()
    |> decode_remove_response
  end

  defp decode_remove_response(%HTTPoison.Response{status_code: status_code}) do
    case status_code do
      204 -> {:ok}
      400 -> {:error, "Bad parameter"}
      404 -> {:error, "No such container"}
      409 -> {:error, "Conflict"}
      500 -> {:error, "Server error"}
      code -> {:error, "Unknown code: #{code}"}
    end
  end

  @doc """
  Starts a newly created container.
  """
  def start(id) do
    start(id, %{})
  end

  @doc """
  Starts a newly created container with a specified start config.
  The start config was deprecated as of v1.15 of the API, and all
  host parameters should be in the create configuration.
  """
  def start(id, conf) do
    "#{@base_uri}/#{id}/start"
    |> Docker.Client.post(conf)
    |> decode_start_response
  end

  defp decode_start_response(%HTTPoison.Response{status_code: status_code}) do
    case status_code do
      204 -> {:ok}
      304 -> {:error, "Container already started"}
      404 -> {:error, "No such container"}
      500 -> {:error, "Server error"}
      code -> {:error, "Unknown code: #{code}"}
    end
  end

  @doc """
  Stop a running container.
  """
  def stop(id) do
    "#{@base_uri}/#{id}/stop"
    |> Docker.Client.post()
    |> decode_stop_response
  end

  defp decode_stop_response(%HTTPoison.Response{body: body, status_code: status_code}) do
    Logger.debug(fn -> "Decoding Docker API response: #{Kernel.inspect(body)}" end)

    case status_code do
      204 -> {:ok}
      304 -> {:error, "Container already stopped"}
      404 -> {:error, "No such container"}
      500 -> {:error, "Server error"}
      _ -> {:error, "Unknow status"}
    end
  end

  @doc """
  Kill a running container.
  """
  def kill(id) do
    "#{@base_uri}/#{id}/kill"
    |> Docker.Client.post()
    |> decode_kill_response
  end

  defp decode_kill_response(%HTTPoison.Response{status_code: status_code}) do
    case status_code do
      204 -> {:ok}
      304 -> {:error, "Container already killed"}
      404 -> {:error, "No such container"}
      500 -> {:error, "Server error"}
      code -> {:error, "Unknown code: #{code}"}
    end
  end

  @doc """
  Restart a container.
  """
  def restart(id) do
    "#{@base_uri}/#{id}/restart"
    |> Docker.Client.post()
    # same responses as the start endpoint
    |> decode_start_response
  end

  @default_log_opts [:stdout, :stderr]

  @doc """
  Return real-time logs from server as a stream.
  """
  def stream_logs(id, opts \\ []) do
    query_opts = Enum.filter(opts, fn {key, _} -> key in @default_log_opts end)

    query = [follow: true, since: 0] |> Keyword.merge(query_opts) |> URI.encode_query()

    url = "/containers/#{id}/logs?#{query}"

    Stream.resource(
      fn -> start_streamming_logs(url) end,
      fn {id, status, body_or_stream} -> receive_logs({id, status, body_or_stream}) end,
      fn id -> stop_streaming_logs(id) end
    )
  end

  def start_streamming_logs(url) do
    %HTTPoison.AsyncResponse{id: id} = Docker.Client.stream(:get, url)
    {id, :keepalive, nil}
  end

  defp receive_logs({id, :kill, _}) do
    {:halt, id}
  end

  defp receive_logs({id, :keepalive, body_or_stream}) do
    receive do
      %HTTPoison.AsyncStatus{id: ^id, code: code} ->
        case code do
          101 -> {[{:ok, "Logs returned as a stream"}], {id, :keepalive, :stream}}
          200 -> {[{:ok, "Logs returned as a string in response body"}], {id, :keepalive, :body}}
          404 -> {[{:error, "No such task"}], {id, :kill, body_or_stream}}
          500 -> {[{:error, "Server error"}], {id, :kill, body_or_stream}}
          _ -> {[{:error, "Unknow error"}], {id, :kill, body_or_stream}}
        end

      %HTTPoison.AsyncHeaders{id: ^id, headers: _headers} ->
        {[], {id, :keepalive, body_or_stream}}

      %HTTPoison.AsyncChunk{id: ^id, chunk: chunk} ->
        case body_or_stream do
          :stream ->
            log = Docker.Misc.parse_stream_log(chunk)

            {[{:log, log}], {id, :keepalive, :stream}}
          :body ->
            {[{:log, chunk}], {id, :keepalive, :body}}
        end

      %HTTPoison.AsyncEnd{id: ^id} ->
        {[{:end, "Finished streaming"}], {id, :kill, body_or_stream}}
    end
  end

  defp stop_streaming_logs(id) do
    :hackney.stop_async(id)
  end

  @doc """
  Given the name of a container, returns any matching IDs.
  """
  def find_ids(name, :partial) do
    {:ok, containers} = Docker.Containers.list()
    name = name |> Docker.Names.container_safe() |> Docker.Names.api()

    ids =
      containers
      |> Enum.filter(&match_partial_name(&1, name))
      |> Enum.map(& &1["Id"])

    case length(ids) > 0 do
      true -> {:ok, ids}
      _ -> {:err, "No containers found"}
    end
  end

  def find_ids(name) do
    {:ok, containers} = Docker.Containers.list()
    name = name |> Docker.Names.container_safe() |> Docker.Names.api()

    ids =
      containers
      |> Enum.filter(&(name in &1["Names"]))
      |> Enum.map(& &1["Id"])

    case length(ids) > 0 do
      true -> {:ok, ids}
      _ -> {:err, "No containers found"}
    end
  end

  defp match_partial_name(container, name) do
    container["Names"]
    |> Enum.any?(&(&1 == name || String.starts_with?(&1, "#{name}_")))
  end
end
