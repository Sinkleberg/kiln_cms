defmodule KilnCMS.CMS.Changes.NotifyTaxonomyWebhooks do
  @moduledoc """
  After a taxonomy write commits, dispatch `<type>.<event>` (`tag.created`,
  `tag_group.updated`, `category.deleted`, …) through `KilnCMS.Webhooks.dispatch/4`
  (#1965). `KilnCMS.CMS.Taxonomy` attaches it to the `:create`, `:update` and
  `:destroy` actions every taxonomy resource has, which are the only write
  actions they have:

      change {KilnCMS.CMS.Changes.NotifyTaxonomyWebhooks, event: "created"}

  ## Payload

  `id`, `slug`, `name` and `updated_at`, plus `tag_group_id` for a tag.
  `updated_at` lets a receiver drop a retried delivery that arrives after a
  later one. On `updated` the payload adds `previous_slug` when the slug
  changed, and for a tag `previous_tag_group_id` when it moved group, so a
  receiver can evict entries keyed by the old values. On `deleted` it is the
  record as it was.

  The previous values are read from `changeset.data`, which is the record the
  caller passed in. Ash does not re-read it. A caller holding a stale record
  (for example, a form opened before someone else renamed the tag) produces a
  stale `previous_slug`, so a receiver should treat it as a hint.

  ## When it runs

  In an `after_transaction` hook, for the same reason as
  `KilnCMS.CMS.Changes.NotifyWebhooks`: after COMMIT, best-effort. A write
  that fails dispatches nothing. The change implements `atomic/3` as well
  as `change/3`, because Category's `:update` and every taxonomy `:destroy`
  are atomic, and a change without `atomic/3` would make them refuse to run.
  It adds a hook and writes no attribute, so the atomic form is the same
  change.

  `withdraws: false`: a deleted tag is not a withdrawn document, so it is never
  a retraction (`KilnCMS.Webhooks.retraction?/1` says so too).
  """
  use Ash.Resource.Change

  alias KilnCMS.Webhooks

  @impl true
  def init(opts) do
    if Keyword.get(opts, :event) in ~w(created updated deleted),
      do: {:ok, opts},
      else: {:error, "event must be one of created, updated, deleted"}
  end

  @impl true
  def change(changeset, opts, _context) do
    event = Keyword.fetch!(opts, :event)

    Ash.Changeset.after_transaction(changeset, fn
      changeset, {:ok, %{} = record} ->
        Webhooks.dispatch(
          "#{record.__struct__.__kiln_taxonomy_type__()}.#{event}",
          payload(event, changeset, record),
          record.org_id,
          withdraws: false
        )

        {:ok, record}

      _changeset, other ->
        other
    end)
  end

  @impl true
  def atomic(changeset, opts, context), do: {:ok, change(changeset, opts, context)}

  @doc false
  # The `data` of a webhook: what identifies the term, plus what changed.
  def payload("updated", changeset, record) do
    record
    |> base()
    |> put_previous(:previous_slug, changeset, record, :slug)
    |> put_previous(:previous_tag_group_id, changeset, record, :tag_group_id)
  end

  def payload(_event, _changeset, record), do: base(record)

  defp base(record) do
    map = %{
      id: record.id,
      slug: record.slug,
      name: record.name,
      updated_at: record.updated_at
    }

    if Map.has_key?(record, :tag_group_id),
      do: Map.put(map, :tag_group_id, record.tag_group_id),
      else: map
  end

  # Only a field the action wrote, and whose value it moved: Ash drops a write
  # equal to the current value, and a field nobody wrote has no "previous".
  defp put_previous(map, key, changeset, record, field) do
    old = Map.get(changeset.data, field)

    if Map.has_key?(record, field) and Ash.Changeset.changing_attribute?(changeset, field) and
         old != Map.get(record, field),
       do: Map.put(map, key, old),
       else: map
  end
end
