defmodule Docker.Exec do
  @moduledoc """
  Docker exec methods.
  """
  require Logger
  @base_exec_uri "/exec"
  @base_containers_uri "/containers"

  @doc """
  Run a command inside a running container.
  """
  def create(id, conf) do
    "#{@base_containers_uri}/#{id}/exec"
    |> Docker.Client.post(conf)
    |> decode_create_response
  end

  defp decode_create_response(%HTTPoison.Response{body: body, status_code: status_code}) do
    with 201 <- status_code,
         {:ok, res} <- Poison.decode(body) do
      {:ok, res}
    else
      404 -> {:error, "No such container"}
      409 -> {:error, "container is paused"}
      500 -> {:error, "Server Error"}
      _ -> {:error, "Unknown error #{Kernel.inspect(body)}"}
    end
  end

  @doc """
  Start an exec instance by ID.
  """
  def start(id, conf) do
    "#{@base_exec_uri}/#{id}/start"
    |> Docker.Client.post(conf)
    |> decode_start_response
  end

  defp decode_start_response(%HTTPoison.Response{status_code: status_code}) do
    case status_code do
      200 -> {:ok}
      404 -> {:error, "No such instance"}
      409 -> {:error, "No such exec instance"}
      code -> {:error, "Unknown error #{code}"}
    end
  end

  @doc """
  Inspect an exec by ID.
  """
  def inspect(id) do
    "#{@base_exec_uri}/#{id}/inspec"
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
            {:error, "No such exec instance"}

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
end
