defmodule KilnCMSWeb.Plugs.E2ECollabTest do
  @moduledoc false
  # Flips the VM-global `:collab_prototype`, which every editor mount reads —
  # so not async (see `KilnCMS.Collab.Crdt.enabled?/0`).
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias KilnCMSWeb.Plugs.E2ECollab

  setup do
    previous = Application.get_env(:kiln_cms, :collab_prototype)
    on_exit(fn -> Application.put_env(:kiln_cms, :collab_prototype, previous) end)
  end

  defp call(method, params) do
    conn(method, "/", params) |> E2ECollab.call(E2ECollab.init([]))
  end

  test "POST switches the flag and answers with the value it had" do
    Application.put_env(:kiln_cms, :collab_prototype, false)

    conn = call(:post, %{"enabled" => "true"})
    assert conn.status == 200
    assert conn.halted
    assert Jason.decode!(conn.resp_body) == %{"enabled" => true, "was" => false}
    assert KilnCMS.Collab.Crdt.enabled?()

    conn = call(:post, %{"enabled" => false})
    assert Jason.decode!(conn.resp_body) == %{"enabled" => false, "was" => true}
    refute KilnCMS.Collab.Crdt.enabled?()
  end

  test "anything but true or false is refused and leaves the flag alone" do
    Application.put_env(:kiln_cms, :collab_prototype, false)

    conn = call(:post, %{"enabled" => "yes"})
    assert conn.status == 400
    refute KilnCMS.Collab.Crdt.enabled?()
  end

  test "a GET changes nothing" do
    Application.put_env(:kiln_cms, :collab_prototype, false)

    conn = call(:get, %{"enabled" => "true"})
    assert conn.status == 405
    assert get_resp_header(conn, "allow") == ["POST"]
    refute KilnCMS.Collab.Crdt.enabled?()
  end
end
