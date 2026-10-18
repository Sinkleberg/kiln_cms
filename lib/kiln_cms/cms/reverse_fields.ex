defmodule KilnCMS.CMS.ReverseFields do
  @moduledoc """
  Reverse fields (R4 in `docs/relationships-plan.md`): the other side of a
  `:reference` custom field, as its targets see it.

  A reference definition that names an `inverse_label` / `inverse_name`
  ("Recipes using this ingredient", `used_in_recipes`) gives every record of
  each type it may point at a **reverse field**: the records that connect to
  it through that field. Nothing is stored for it. It is read from the edges
  the reference already writes (`KilnCMS.CMS.ContentLinks`): `kind:
  :reference`, this `field`, from this `source_type`, at this `target_id`.

  ## Who sees what

  `rows/3` reads as the caller, twice over, so it is the both-ends read rule
  unchanged: the edges through `ContentLink`'s read policy, which keeps an
  edge only when the reader may read both of its ends, and the sources
  through their own type's read policy. A reader never meets a draft source
  they could not have opened directly, and the count counts only what they
  may see.

  Which reverse fields a type has is schema, not content, so `for_type/2`
  reads the definitions as the cms registry reader, the way the editor and
  the schema export read a type's own fields.
  """

  alias KilnCMS.CMS
  alias KilnCMS.CMS.ContentTypes
  alias KilnCMS.CMS.FieldDefinition

  @typedoc """
  One reverse field of a type: its own `name` and `label`, and the reference
  it mirrors — `field` on `source_type` records, whose definition is
  `definition` (with its link fields loaded).
  """
  @type t :: %{
          name: String.t(),
          label: String.t(),
          field: String.t(),
          source_type: String.t(),
          source_label: String.t(),
          definition: FieldDefinition.t()
        }

  @typedoc "One record that connects to the target, with its connection's edge."
  @type row :: %{source: struct(), link: struct()}

  @doc """
  The reverse fields records of `type` show, in the source fields' order.
  `type` is a content type name (`"page"`, a dynamic type's name) or atom.
  A definition whose owning type no longer exists is left out.
  """
  @spec for_type(atom() | String.t() | nil, Ash.UUID.t() | struct() | nil) :: [t()]
  def for_type(nil, _org), do: []

  def for_type(type, org) do
    org_id = KilnCMS.Accounts.org_id(org)

    type
    |> to_string()
    |> CMS.reverse_field_definitions_for!(
      actor: KilnCMS.CMS.Housekeeping.system(:cms_registry),
      authorize_with: :error,
      tenant: org_id
    )
    |> Enum.flat_map(&describe(&1, org_id))
  end

  @doc "The reverse field of `type` named `name`, or nil."
  @spec find(atom() | String.t() | nil, String.t(), Ash.UUID.t() | struct() | nil) :: t() | nil
  def find(type, name, org), do: type |> for_type(org) |> Enum.find(&(&1.name == name))

  defp describe(definition, org_id) do
    case source(definition, org_id) do
      nil ->
        []

      %{type: source_type, label: source_label} ->
        [
          %{
            name: definition.inverse_name,
            label: definition.inverse_label,
            field: definition.name,
            source_type: to_string(source_type),
            source_label: source_label,
            definition: definition
          }
        ]
    end
  end

  # The content type owning the reference: a compiled type by name, or the
  # dynamic type whose definition id it carries.
  defp source(%{type_definition_id: nil, content_type: type}, org_id) do
    if FieldDefinition.orphaned?(%{type_definition_id: nil, content_type: type}),
      do: nil,
      else: ContentTypes.get(type, org_id)
  end

  defp source(%{type_definition_id: id}, org_id),
    do: org_id |> ContentTypes.dynamic_all() |> Enum.find(&(&1.definition.id == id))

  @doc """
  One page of the records connecting to `target` through `reverse`, as the
  caller (`:actor`, `:tenant`) may see them, ordered by title — and how many
  there are in all. `:offset` and `:limit` (default 10) pick the page.

  Returns `%{rows: [row()], total: non_neg_integer()}`. Each row carries the
  connection's edge as `link`: its `metadata` holds the link-field values
  (R3), its `position` the target's place in the source's own list.
  """
  @spec rows(struct(), t(), keyword()) :: %{rows: [row()], total: non_neg_integer()}
  def rows(target, reverse, opts) do
    tenant = Keyword.get(opts, :tenant) || target.org_id
    read_opts = [actor: Keyword.get(opts, :actor), tenant: tenant]

    edges =
      CMS.list_content_links!(
        read_opts ++
          [
            query: [
              filter: [
                target_id: target.id,
                kind: :reference,
                field: reverse.field,
                source_type: reverse.source_type
              ]
            ]
          ]
      )
      |> Map.new(&{&1.source_id, &1})

    page(edges, reverse.source_type, read_opts, opts)
  end

  defp page(edges, _source_type, _read_opts, _opts) when map_size(edges) == 0,
    do: %{rows: [], total: 0}

  defp page(edges, source_type, read_opts, opts) do
    filter = [id: [in: Map.keys(edges)]]

    total = ContentTypes.count!(source_type, read_opts ++ [query: [filter: filter]])

    sources =
      ContentTypes.list!(
        source_type,
        read_opts ++
          [
            query: [
              filter: filter,
              sort: [title: :asc, id: :asc],
              offset: Keyword.get(opts, :offset, 0),
              limit: Keyword.get(opts, :limit, 10)
            ]
          ]
      )

    %{rows: Enum.map(sources, &%{source: &1, link: Map.fetch!(edges, &1.id)}), total: total}
  end
end
