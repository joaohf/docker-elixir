defmodule Docker.Networks do
  @moduledoc """
  Docker networks methods.
  """
  require Logger
  @base_uri "/networks"

  @doc """
  List networks.
  """
  def list() do
    Docker.Client.get("#{@base_uri}")
    |> decode_list_response
  end

  defp decode_list_response(%HTTPoison.Response{body: body, status_code: status_code}) do
    Logger.debug fn -> "Decoding Docker API response: #{Kernel.inspect body}" end
    case Poison.decode(body) do
      {:ok, dict} ->
        case status_code do
          200 -> {:ok, dict}
          500 -> {:error, "Server error"}
          code -> {:error, "Unknown code: #{code}"}
        end
      {:error, message} -> {:error, message}
    end
  end

  def create(conf) do
    "#{@base_uri}/create"
    |> Docker.Client.post(conf)
    |> decode_create_response
  end

  defp decode_create_response(%HTTPoison.Response{body: body, status_code: status_code}) do
    with 201 <- status_code,
        {:ok, res} <- Poison.decode(body) do
      {:ok, res}
    else
      403 -> {:error, "Operation not supported for pre-defined networks"}
      404 -> {:error, "Plugin not found"}
      500 -> {:error, "Server Error"}
      _ -> {:error, "Unknown error #{Kernel.inspect(body)}"}
    end
  end

  def remove(id) do
    "#{@base_uri}/#{id}"
    |> Docker.Client.delete
    |> decode_remove_response
  end

  defp decode_remove_response(%HTTPoison.Response{status_code: status_code}) do
    case status_code do
      204 -> {:ok}
      404 -> {:error, "No such network"}
      500 -> {:error, "Server error"}
      code -> {:error, "Unknown code: #{code}"}
    end
  end


  def connect(conf, id) do
      "#{@base_uri}/#{id}/connect"
      |> Docker.Client.post(conf)
      |> decode_connect_disconnect_response
  end

  def disconnect(conf, id) do
    "#{@base_uri}/#{id}/disconnect"
    |> Docker.Client.post(conf)
    |> decode_connect_disconnect_response
  end

  defp decode_connect_disconnect_response(%HTTPoison.Response{status_code: status_code}) do
    case status_code do
      200 -> {:ok}
      403 -> {:error, "Operation not supported for swarm scoped networks"}
      404 -> {:error, "Network or container not found"}
      500 -> {:error, "Server error"}
      code -> {:error, "Unknown code: #{code}"}
    end
  end

  def inspect() do
    :ok
  end

  @doc """
  Given the name of a network, returns any matching IDs.
  """
  def find_ids(name) do
    {:ok, networks} = Docker.Networks.list
    ids =
      networks
      |> Enum.filter(&(name == &1["Name"]))
      |> Enum.map(&(&1["Id"]))
    case length(ids) > 0 do
      true -> {:ok, ids}
      _ -> {:err, "No networks found"}
    end
  end
end
