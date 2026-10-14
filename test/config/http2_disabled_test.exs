defmodule KilnCMS.Config.Http2DisabledTest do
  @moduledoc """
  Pins that the endpoint's listener does not speak HTTP/2
  (EEF-CVE-2026-105659): Bandit through 1.12.5 lets a client that trickles
  WINDOW_UPDATE frames pin an HTTP/2 stream's process indefinitely.

  The suite's endpoint runs no server, so this starts a real Bandit listener
  with the endpoint's own `:http` options (as `config/runtime.exs` left them)
  and sends it an h2c prior-knowledge preface over a raw socket. An edit to
  the config is what gets tested, not a copy of it.
  """
  use ExUnit.Case, async: true

  defmodule Hello do
    @moduledoc false
    def init(opts), do: opts
    def call(conn, _opts), do: Plug.Conn.send_resp(conn, 200, "ok")
  end

  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  setup do
    http_opts =
      :kiln_cms
      |> Application.fetch_env!(KilnCMSWeb.Endpoint)
      |> Keyword.fetch!(:http)
      |> Keyword.merge(port: 0, ip: :loopback, startup_log: false)

    server = start_supervised!({Bandit, [plug: Hello] ++ http_opts})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)
    {:ok, port: port}
  end

  defp connect(port),
    do: :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], 1_000)

  test "the endpoint's HTTP options turn HTTP/2 off" do
    http = Application.fetch_env!(:kiln_cms, KilnCMSWeb.Endpoint)[:http]
    assert get_in(http, [:http_2_options, :enabled]) == false
  end

  test "an h2c prior-knowledge connection is closed, not answered", %{port: port} do
    {:ok, socket} = connect(port)
    :ok = :gen_tcp.send(socket, @preface)

    # With HTTP/2 on, Bandit replies with a SETTINGS frame here.
    assert :gen_tcp.recv(socket, 0, 1_000) == {:error, :closed}
  end

  test "HTTP/1.1 is still served", %{port: port} do
    {:ok, socket} = connect(port)
    :ok = :gen_tcp.send(socket, "GET / HTTP/1.1\r\nhost: localhost\r\nconnection: close\r\n\r\n")

    assert {:ok, "HTTP/1.1 200" <> _} = :gen_tcp.recv(socket, 0, 1_000)
  end
end
