defmodule KilnCMSWeb.ContentEditor.ReverseField do
  @moduledoc """
  The content editor's **reverse field** (R4 in `docs/relationships-plan.md`):
  the other side of a `:reference` field that names one, on each record it may
  point at — "Recipes using this ingredient" on an Ingredient, for a Recipe's
  `ingredients` field.

  It lists the records connecting to this one through that field, each with
  its connection's details (the link fields, R3), ordered by title and a page
  at a time. Nothing in it belongs to the editor form: the connection is the
  *source* record's value, so the list is read-only here and changes from the
  source's own editor, which each row links to.

  Reading is `KilnCMS.CMS.ReverseFields.rows/3`, as the editor's actor, so the
  both-ends read rule holds: an editor scoped away from the source type is
  not shown its records, and the count counts only what they may open.

  Rows render with the reference picker's own row
  (`KilnCMSWeb.ContentEditor.ReferencePicker.row/1`, `readonly`), so both
  sides of a relationship look the same.
  """

  use KilnCMSWeb, :live_component

  alias KilnCMS.CMS.FieldDefinition
  alias KilnCMS.CMS.ReverseFields
  alias KilnCMSWeb.ContentEditor.ReferencePicker

  @page_size 10

  @doc "How many rows one page shows."
  @spec page_size() :: pos_integer()
  def page_size, do: @page_size

  @impl true
  def mount(socket), do: {:ok, assign(socket, :offset, 0)}

  @impl true
  def update(assigns, socket) do
    # The parent re-renders the panel on every keystroke; the list only moves
    # when the record does (a save), so it is read again only then.
    stale? = Map.get(socket.assigns, :loaded) != version(assigns.record)
    socket = assign(socket, assigns)

    {:ok,
     if(stale?, do: socket |> load() |> assign(:loaded, version(assigns.record)), else: socket)}
  end

  defp version(record), do: {record.id, Map.get(record, :updated_at)}

  @impl true
  def handle_event("reverse_page", %{"offset" => offset}, socket) do
    offset =
      case Integer.parse(to_string(offset)) do
        {n, ""} when n >= 0 -> n
        _other -> 0
      end

    {:noreply, socket |> assign(:offset, offset) |> load()}
  end

  defp load(socket) do
    %{record: record, reverse: reverse, actor: actor, tenant: tenant, offset: offset} =
      socket.assigns

    page =
      ReverseFields.rows(record, reverse,
        actor: actor,
        tenant: tenant,
        offset: offset,
        limit: @page_size
      )

    # A page past the end (rows removed since) falls back to the last page.
    if page.rows == [] and offset > 0 and page.total > 0 do
      socket |> assign(:offset, last_offset(page.total)) |> load()
    else
      socket
      |> assign(:rows, page.rows)
      |> assign(:total, page.total)
      |> assign(:link_fields, FieldDefinition.link_fields(reverse.definition))
    end
  end

  defp last_offset(total), do: div(total - 1, @page_size) * @page_size

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :root,
        "reverse-field-#{assigns.reverse.source_type}-#{assigns.reverse.field}"
      )

    ~H"""
    <div
      id={@root}
      role="group"
      aria-labelledby={"#{@root}-label"}
      aria-describedby={"#{@root}-hint"}
      data-reverse-field={@reverse.name}
    >
      <div class="mb-1 flex items-baseline justify-between gap-2">
        <span id={"#{@root}-label"} class="flex items-center gap-1.5 text-sm font-medium">
          <.icon name="hero-arrow-uturn-left" class="size-3.5 text-base-content/40" />
          {@reverse.label}
        </span>
        <span :if={@total > 0} class="text-xs tabular-nums text-base-content/60">
          {ngettext("%{count} connected", "%{count} connected", @total)}
        </span>
      </div>
      <p id={"#{@root}-hint"} class="mb-1.5 text-xs text-base-content/60">
        {gettext("%{type} records that connect to this one through their %{field} field.",
          type: @reverse.source_label,
          field: @reverse.definition.label
        )}
      </p>

      <ol
        :if={@rows != []}
        id={"#{@root}-items"}
        aria-label={@reverse.label}
        class="divide-y divide-base-content/10 overflow-hidden rounded-md border border-base-content/10"
      >
        <ReferencePicker.row
          :for={row <- @rows}
          id={"#{@root}-#{row.source.id}"}
          item={item(row, @reverse)}
          readonly
        >
          <:extra>
            <.connection_details
              id={"#{@root}-#{row.source.id}-details"}
              fields={@link_fields}
              values={row.link.metadata}
              position={@reverse.definition.multiple && row.link.position}
            />
          </:extra>
        </ReferencePicker.row>
      </ol>

      <p :if={@rows == []} class="text-sm text-base-content/60">
        {gettext("Nothing connects to this record yet.")}
      </p>

      <nav
        :if={@total > length(@rows)}
        aria-label={gettext("%{field} pages", field: @reverse.label)}
        class="mt-1.5 flex items-center justify-between gap-2 text-xs text-base-content/60"
      >
        <span class="tabular-nums">
          {gettext("%{first}–%{last} of %{total}",
            first: @offset + 1,
            last: @offset + length(@rows),
            total: @total
          )}
        </span>
        <span class="flex items-center gap-1">
          <button
            type="button"
            phx-click="reverse_page"
            phx-value-offset={max(@offset - page_size(), 0)}
            phx-target={@myself}
            disabled={@offset == 0}
            class="btn btn-ghost btn-sm"
          >
            <.icon name="hero-chevron-left" class="size-3.5" />
            {gettext("Previous")}
          </button>
          <button
            type="button"
            phx-click="reverse_page"
            phx-value-offset={@offset + page_size()}
            phx-target={@myself}
            disabled={@offset + length(@rows) >= @total}
            class="btn btn-ghost btn-sm"
          >
            {gettext("Next")}
            <.icon name="hero-chevron-right" class="size-3.5" />
          </button>
        </span>
      </nav>
    </div>
    """
  end

  defp item(%{source: source}, reverse) do
    %{
      id: source.id,
      title: source.title,
      state: source.state,
      type_label: reverse.source_label,
      href: ~p"/editor/content/#{reverse.source_type}/#{source.id}"
    }
  end

  attr :id, :string, required: true
  attr :fields, :list, required: true
  attr :values, :map, required: true
  attr :position, :any, default: nil

  # The connection's details as text: its link-field values (R3) in the
  # field's order, and — for a list — this record's place in the source's list.
  defp connection_details(assigns) do
    assigns =
      assign(
        assigns,
        :shown,
        for(
          field <- assigns.fields,
          (value = Map.get(assigns.values || %{}, field.name)) not in [nil, ""],
          do: {field, value}
        )
      )

    ~H"""
    <p
      :if={@shown != [] or is_integer(@position)}
      id={@id}
      class="mt-1 flex flex-wrap items-center gap-1.5 text-xs text-base-content/70"
    >
      <span
        :if={is_integer(@position)}
        class="rounded bg-base-200 px-1.5 py-0.5 tabular-nums"
      >
        {gettext("No. %{position} in its list", position: @position + 1)}
      </span>
      <span :for={{field, value} <- @shown} class="rounded bg-base-200 px-1.5 py-0.5">
        <span class="text-base-content/50">{field.label}:</span> {format(value)}
      </span>
    </p>
    """
  end

  defp format(true), do: gettext("Yes")
  defp format(false), do: gettext("No")
  defp format(value), do: to_string(value)
end
