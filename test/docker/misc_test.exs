defmodule MiscTestDos do
  use ExUnit.Case

  test "info" do
    assert {:ok, _} = Docker.Misc.info()
  end

  test "version" do
    assert {:ok, %{"ApiVersion" => _, "Version" => _}} = Docker.Misc.version()
  end

  test "ping" do
    assert {:ok, _} = Docker.Misc.ping()
  end

  test "get events and stream response" do
    conf = %{
      "AttachStdin" => false,
      "Env" => [],
      "Image" => "hello-world:latest",
      "Volumes" => %{},
      "ExposedPorts" => %{}
    }

    stream = Docker.Misc.stream_events()
    parent = self()

    spawn(fn ->
      Enum.map(stream, fn event -> send(parent, event) end)
    end)

    {:ok, %{"Id" => id}} = Docker.Containers.create(conf)
    assert_receive {:ok, _}
    assert_receive {:event, %{"Action" => "create"}}
    Docker.Containers.remove(id)
  end

  test "get logs and stream response" do
    conf = %{
      "AttachStdin" => false,
      "Env" => [],
      "Image" => "httpd:2.4",
      "Volumes" => %{},
      "ExposedPorts" => %{}
    }

    {:ok, %{"Id" => id}} = Docker.Containers.create(conf)
    {:ok} = Docker.Containers.start(id)

    stream = Docker.Containers.stream_logs(id, stderr: true)
    parent = self()

    spawn(fn ->
      Enum.map(stream, fn event -> send(parent, event) end)
    end)

    assert_receive {:ok, "Logs returned as a string in response body"}
    assert_receive {:log, _}, 1000
    assert_receive {:log, _}, 1000

    Docker.Containers.stop(id)
    Docker.Containers.remove(id)
  end
end
