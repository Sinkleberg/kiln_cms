defmodule KilnCMS.CMS.RelationshipFiltersTest do
  @moduledoc """
  Workstream R6 of `docs/relationships-plan.md`: `custom_filter`'s
  relationship operators — `has`, `has_all`, `has_none` and `count` on a
  `:reference` field (over its `content_links` edges), and `has` / `has_all`
  / `has_none` on the built-in `tags` and `related_<type>s` — and the
  read-side rule that a filter cannot be used to probe for a draft target.
  """
  use KilnCMS.DataCase, async: true

  alias KilnCMS.CMS

  defp user(role) do
    Ash.Seed.seed!(KilnCMS.Accounts.User, %{
      email: "rfilter-#{System.unique_integer([:positive])}@example.com",
      hashed_password: Bcrypt.hash_pwd_salt("password123456"),
      confirmed_at: DateTime.utc_now(),
      role: role
    })
  end

  defp slug, do: "rfilter-#{System.unique_integer([:positive])}"

  defp page!(admin, title, opts \\ []) do
    page = CMS.create_page!(%{title: title, slug: slug()}, actor: admin)

    if Keyword.get(opts, :publish, true),
      do: CMS.publish_page!(page, %{}, actor: admin),
      else: page
  end

  defp reference_field!(admin, attrs \\ %{}) do
    name = "refs_#{System.unique_integer([:positive])}"

    CMS.create_field_definition!(
      Map.merge(
        %{
          content_type: :post,
          name: name,
          label: "Refs",
          field_type: :reference,
          target_type: "page",
          multiple: true
        },
        attrs
      ),
      actor: admin
    )

    name
  end

  defp post!(admin, attrs) do
    %{title: "Post", slug: slug()}
    |> Map.merge(attrs)
    |> CMS.create_post!(actor: admin)
    |> then(&CMS.publish_post!(&1, %{}, actor: admin))
  end

  # The ids of the posts `filter` matches for `actor`, restricted to `scope`
  # (this test's rows — the sandbox is shared with other async tests' posts).
  defp matching(filter, actor, scope) do
    %{custom_filter: filter}
    |> CMS.list_posts!(actor: actor)
    |> Enum.map(& &1.id)
    |> Enum.filter(&(&1 in Enum.map(scope, fn post -> post.id end)))
    |> Enum.sort()
  end

  defp sorted(posts), do: posts |> Enum.map(& &1.id) |> Enum.sort()

  defp error!(filter, actor \\ nil) do
    assert {:error, error} = CMS.list_posts(%{custom_filter: filter}, actor: actor)
    Exception.message(error)
  end

  setup do
    %{admin: user(:admin)}
  end

  describe "a list of references" do
    setup %{admin: admin} do
      name = reference_field!(admin)
      [a, b, c] = for t <- ~w(A B C), do: page!(admin, t)
      ab = post!(admin, %{custom_fields: %{name => [a.id, b.id]}})
      bc = post!(admin, %{custom_fields: %{name => [b.id, c.id]}})
      none = post!(admin, %{})
      %{name: name, a: a, b: b, c: c, ab: ab, bc: bc, none: none, scope: [ab, bc, none]}
    end

    test "has matches any of the ids", ctx do
      m = &matching(%{ctx.name => %{"has" => &1}}, nil, ctx.scope)

      assert m.([ctx.a.id]) == [ctx.ab.id]
      assert m.([ctx.a.id, ctx.c.id]) == sorted([ctx.ab, ctx.bc])
      # A lone id is a one-item list.
      assert m.(ctx.b.id) == sorted([ctx.ab, ctx.bc])
      assert m.([Ash.UUID.generate()]) == []
    end

    test "has_all matches only records holding every id", ctx do
      m = &matching(%{ctx.name => %{"has_all" => &1}}, nil, ctx.scope)

      assert m.([ctx.a.id, ctx.b.id]) == [ctx.ab.id]
      assert m.([ctx.b.id]) == sorted([ctx.ab, ctx.bc])
      assert m.([ctx.a.id, ctx.c.id]) == []
      # A repeated id counts once.
      assert m.([ctx.a.id, ctx.a.id]) == [ctx.ab.id]
    end

    test "has_none matches records holding none of the ids, empty ones included", ctx do
      m = &matching(%{ctx.name => %{"has_none" => &1}}, nil, ctx.scope)

      assert m.([ctx.a.id]) == sorted([ctx.bc, ctx.none])
      assert m.([ctx.a.id, ctx.c.id]) == [ctx.none.id]
    end

    test "count compares the number of targets", ctx do
      m = &matching(%{ctx.name => %{"count" => &1}}, nil, ctx.scope)

      assert m.(2) == sorted([ctx.ab, ctx.bc])
      assert m.("0") == [ctx.none.id]
      assert m.(%{"eq" => 0}) == [ctx.none.id]
      assert m.(%{"gt" => 0}) == sorted([ctx.ab, ctx.bc])
      assert m.(%{"gte" => 2}) == sorted([ctx.ab, ctx.bc])
      assert m.(%{"lt" => 2}) == [ctx.none.id]
      assert m.(%{"lte" => 1}) == [ctx.none.id]
      assert m.(%{"gt" => 0, "lt" => 2}) == []
    end

    test "operators combine with each other and with eq/in", ctx do
      assert matching(
               %{ctx.name => %{"has" => [ctx.b.id], "has_none" => [ctx.c.id]}},
               nil,
               ctx.scope
             ) ==
               [ctx.ab.id]

      # R1's snapshot operators keep their meaning on the same field.
      assert matching(%{ctx.name => %{"eq" => ctx.c.id, "count" => 2}}, nil, ctx.scope) ==
               [ctx.bc.id]
    end

    test "edges follow the live value", ctx do
      # A draft's edits are live (a published record's go to its working copy).
      {:ok, draft} =
        CMS.create_post(%{title: "D", slug: slug(), custom_fields: %{ctx.name => [ctx.a.id]}},
          actor: ctx.admin
        )

      has_a = %{ctx.name => %{"has" => [ctx.a.id]}}
      assert matching(has_a, ctx.admin, [draft]) == [draft.id]

      CMS.update_post!(draft, %{custom_fields: %{ctx.name => [ctx.c.id]}}, actor: ctx.admin)
      assert matching(has_a, ctx.admin, [draft]) == []
    end
  end

  describe "a single reference" do
    test "takes the same operators, and eq keeps matching its one id", %{admin: admin} do
      name = reference_field!(admin, %{multiple: false})
      a = page!(admin, "A")
      b = page!(admin, "B")
      pa = post!(admin, %{custom_fields: %{name => a.id}})
      pb = post!(admin, %{custom_fields: %{name => b.id}})
      none = post!(admin, %{})
      scope = [pa, pb, none]

      assert matching(%{name => a.id}, nil, scope) == [pa.id]
      assert matching(%{name => %{"has" => [a.id, b.id]}}, nil, scope) == sorted([pa, pb])
      assert matching(%{name => %{"has_all" => [a.id]}}, nil, scope) == [pa.id]
      assert matching(%{name => %{"has_none" => [a.id]}}, nil, scope) == sorted([pb, none])
      assert matching(%{name => %{"count" => 0}}, nil, scope) == [none.id]
    end
  end

  describe "a draft target cannot be probed" do
    setup %{admin: admin} do
      name = reference_field!(admin)
      live = page!(admin, "Live")
      draft = page!(admin, "Draft", publish: false)
      post = post!(admin, %{custom_fields: %{name => [live.id, draft.id]}})
      %{name: name, live: live, draft: draft, post: post, editor: user(:editor)}
    end

    test "a draft-only match returns nothing to an anonymous reader, the record to an editor",
         ctx do
      filter = %{ctx.name => %{"has" => [ctx.draft.id]}}

      assert matching(filter, nil, [ctx.post]) == []
      assert matching(filter, ctx.editor, [ctx.post]) == [ctx.post.id]
    end

    test "has_all, has_none and count see only what the reader may open", ctx do
      all = %{ctx.name => %{"has_all" => [ctx.live.id, ctx.draft.id]}}
      assert matching(all, nil, [ctx.post]) == []
      assert matching(all, ctx.editor, [ctx.post]) == [ctx.post.id]

      # To an anonymous reader the draft is not there, so holding "none of
      # it" is true — the answer it would get if the draft did not exist.
      none = %{ctx.name => %{"has_none" => [ctx.draft.id]}}
      assert matching(none, nil, [ctx.post]) == [ctx.post.id]
      assert matching(none, ctx.editor, [ctx.post]) == []

      count = %{ctx.name => %{"count" => 1}}
      assert matching(count, nil, [ctx.post]) == [ctx.post.id]
      assert matching(count, ctx.editor, [ctx.post]) == []
      assert matching(%{ctx.name => %{"count" => 2}}, ctx.editor, [ctx.post]) == [ctx.post.id]
    end

    test "publishing the target makes it matchable", ctx do
      CMS.publish_page!(ctx.draft, %{}, actor: ctx.admin)

      assert matching(%{ctx.name => %{"has" => [ctx.draft.id]}}, nil, [ctx.post]) ==
               [ctx.post.id]
    end
  end

  describe "tags" do
    test "has / has_all / has_none", %{admin: admin} do
      [t1, t2, t3] =
        for _ <- 1..3, do: CMS.create_tag!(%{name: "tag-#{slug()}", slug: slug()}, actor: admin)

      p12 = post!(admin, %{tag_ids: [t1.id, t2.id]})
      p23 = post!(admin, %{tag_ids: [t2.id, t3.id]})
      none = post!(admin, %{})
      scope = [p12, p23, none]

      assert matching(%{"tags" => %{"has" => [t1.id, t3.id]}}, nil, scope) == sorted([p12, p23])
      assert matching(%{"tags" => %{"has_all" => [t1.id, t2.id]}}, nil, scope) == [p12.id]
      assert matching(%{"tags" => %{"has_none" => [t1.id]}}, nil, scope) == sorted([p23, none])
    end

    test "only the three set operators apply", %{admin: _admin} do
      assert error!(%{"tags" => %{"count" => 1}}) =~ "tags only supports has/has_all/has_none"
      assert error!(%{"tags" => %{"eq" => Ash.UUID.generate()}}) =~ "only supports"
    end

    test "a custom field named tags keeps the name", %{admin: admin} do
      CMS.create_field_definition!(
        %{content_type: :post, name: "tags", label: "Tags", field_type: :string},
        actor: admin
      )

      post = post!(admin, %{custom_fields: %{"tags" => "red"}})
      assert matching(%{"tags" => "red"}, nil, [post]) == [post.id]
      assert error!(%{"tags" => %{"has" => [Ash.UUID.generate()]}}) =~ "is not a reference"
    end
  end

  describe "related_<type>s" do
    test "has / has_all / has_none, gated like a reference", %{admin: admin} do
      [r1, r2] = for _ <- 1..2, do: post!(admin, %{})
      {:ok, draft} = CMS.create_post(%{title: "Draft", slug: slug()}, actor: admin)
      p = post!(admin, %{related_post_ids: [r1.id, draft.id]})
      q = post!(admin, %{related_post_ids: [r2.id]})
      scope = [p, q]

      assert matching(%{"related_posts" => %{"has" => [r1.id, r2.id]}}, nil, scope) ==
               sorted([p, q])

      assert matching(%{"related_posts" => %{"has_all" => [r1.id]}}, nil, scope) == [p.id]
      assert matching(%{"related_posts" => %{"has_none" => [r1.id]}}, nil, scope) == [q.id]

      # The draft end is invisible to an anonymous reader.
      assert matching(%{"related_posts" => %{"has" => [draft.id]}}, nil, scope) == []

      assert matching(%{"related_posts" => %{"has" => [draft.id]}}, user(:editor), scope) ==
               [p.id]
    end

    test "a reference edge is not related content", %{admin: admin} do
      name =
        reference_field!(admin, %{target_type: "post", multiple: false})

      target = post!(admin, %{})
      referrer = post!(admin, %{custom_fields: %{name => target.id}})

      assert matching(%{"related_posts" => %{"has" => [target.id]}}, nil, [referrer]) == []
      assert matching(%{name => %{"has" => [target.id]}}, nil, [referrer]) == [referrer.id]
    end
  end

  describe "refused input" do
    setup %{admin: admin} do
      %{name: reference_field!(admin)}
    end

    test "names what is wrong", %{name: name, admin: admin} do
      assert error!(%{name => %{"has" => []}}) =~ "needs at least one id"
      assert error!(%{name => %{"has" => ["nope"]}}) =~ ~s("nope" is not an id)
      assert error!(%{name => %{"has" => %{"a" => 1}}}) =~ "takes an id or a list of ids"

      too_many =
        for _ <- 0..CMS.Preparations.CustomFieldQuery.Relations.max_ids(), do: Ash.UUID.generate()

      assert error!(%{name => %{"has_all" => too_many}}) =~ "takes at most 100 ids"

      assert error!(%{name => %{"count" => -1}}) =~ "whole number"
      assert error!(%{name => %{"count" => %{"between" => 1}}}) =~ "unknown count comparison"
      assert error!(%{name => %{"count" => %{}}}) =~ "needs a comparison"

      price = "price_#{System.unique_integer([:positive])}"

      CMS.create_field_definition!(
        %{content_type: :post, name: price, label: "Price", field_type: :integer},
        actor: admin
      )

      assert error!(%{price => %{"has" => [Ash.UUID.generate()]}}) =~
               "has is a relationship operator: custom field #{inspect(price)} (integer) is not a reference"
    end
  end
end
