defmodule KilnCMSWeb.Plugs.E2ECollab do
  @moduledoc """
  Switches the collaborative-editing CRDT prototype (`:collab_prototype`, see
  `KilnCMS.Collab.Crdt.enabled?/0`) on or off for the browser E2E suite.

  `config/e2e.exs` leaves the flag off, as `config/prod.exs` pins it, so every
  editor spec drives the solo rich-text editor production actually runs. Only
  `e2e/tests/collab.spec.js` wants the other path. It turns the flag on here
  before its peers open the editor and puts the previous value back afterwards.
  The flag is VM-global and read on every editor mount, so it applies to
  whatever mounts while it is on. That is safe only because the suite runs one
  spec at a time (`workers: 1`).

  `POST` with `enabled=true|false`. The answer is `{"enabled": new, "was":
  previous}`, and the caller restores `was`. Mounted only inside the router's
  compile-gated dev-tools scope (`dev_routes` / `mailbox_preview`), which
  `KilnCMS.Application` refuses in `:prod`, like `KilnCMSWeb.Plugs.E2EIdentity`.
  That scope runs `protect_from_forgery`, so the spec calls it from a
  signed-in page with the page's CSRF token.
  """

  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: "POST"} = conn, _opts) do
    case conn.params["enabled"] do
      value when value in ["true", "false", true, false] ->
        was = KilnCMS.Collab.Crdt.enabled?()
        now = value in ["true", true]
        Application.put_env(:kiln_cms, :collab_prototype, now)
        reply(conn, 200, %{enabled: now, was: was})

      _other ->
        reply(conn, 400, %{error: "enabled must be true or false"})
    end
  end

  def call(conn, _opts) do
    conn
    |> put_resp_header("allow", "POST")
    |> reply(405, %{error: "POST only"})
  end

  defp reply(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
    |> halt()
  end
end
