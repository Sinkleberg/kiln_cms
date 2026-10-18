# Relationship filters at scale (R6 of docs/relationships-plan.md, open
# question 4): how `custom_filter`'s `has` / `has_all` / `has_none` / `count`
# on a `:reference` field behave on a large edge set.
#
#     MIX_ENV=test MIX_TEST_PARTITION=_bench_r6 mix ash.setup
#     MIX_ENV=test MIX_TEST_PARTITION=_bench_r6 mix run scripts/benchmarks/relationship_filters.exs
#     dropdb kiln_cms_test_bench_r6   # when done
#
# Refuses any database whose name does not contain "bench". Seeds through the
# domain only what the domain must own (the field definition and one template
# page and post), then clones rows and writes edges in SQL: the domain path
# would take hours for this volume, and the filters only read `content_links`
# and the two content tables. Knobs: R6_POSTS, R6_PAGES, R6_DRAFT_PAGES,
# R6_EDGES (per post), R6_FAT_POSTS, R6_FAT_EDGES, R6_RUNS.

alias KilnCMS.CMS
alias KilnCMS.Repo

env_int = fn name, default -> String.to_integer(System.get_env(name, to_string(default))) end

posts_n = env_int.("R6_POSTS", 20_000)
pages_n = env_int.("R6_PAGES", 2_000)
drafts_n = env_int.("R6_DRAFT_PAGES", 100)
edges_n = env_int.("R6_EDGES", 25)
fat_n = env_int.("R6_FAT_POSTS", 100)
fat_edges = env_int.("R6_FAT_EDGES", 1_000)
runs = env_int.("R6_RUNS", 20)

database = Repo.config()[:database]
String.contains?(database, "bench") || raise "refusing to seed #{database}: not a bench database"

org = KilnCMS.Accounts.default_org_id()

user = fn role ->
  Ash.Seed.seed!(KilnCMS.Accounts.User, %{
    email: "r6-#{role}-#{System.unique_integer([:positive])}@example.com",
    hashed_password: Bcrypt.hash_pwd_salt("password123456"),
    confirmed_at: DateTime.utc_now(),
    role: role
  })
end

admin = user.(:admin)
editor = user.(:editor)
opts = [actor: admin, tenant: org]
field = "ingredients"

already? = Repo.query!("SELECT count(*) FROM content_links WHERE field = $1", [field]).rows

if already? == [[0]] do
  CMS.create_field_definition!(
    %{
      content_type: :post,
      name: field,
      label: "Ingredients",
      field_type: :reference,
      target_type: "page",
      multiple: true
    },
    opts
  )

  page = CMS.create_page!(%{title: "Template page", slug: "r6-template-page"}, opts)
  page = CMS.publish_page!(page, %{}, opts)
  post = CMS.create_post!(%{title: "Template post", slug: "r6-template-post"}, opts)
  post = CMS.publish_post!(post, %{}, opts)

  # Clone `n` copies of a row in SQL, with fresh ids and slugs.
  clone = fn table, id, n, overrides ->
    columns =
      Repo.query!(
        """
        SELECT column_name FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = $1 AND is_generated = 'NEVER'
        ORDER BY ordinal_position
        """,
        [table]
      ).rows
      |> List.flatten()

    defaults = %{
      "id" => "gen_random_uuid()",
      "slug" => "t.slug || '-' || g",
      "title" => "t.title || ' ' || g"
    }

    exprs = Enum.map(columns, &(overrides[&1] || defaults[&1] || "t.#{&1}"))

    Repo.query!(
      """
      INSERT INTO #{table} (#{Enum.join(columns, ", ")})
      SELECT #{Enum.join(exprs, ", ")} FROM #{table} t, generate_series(1, $2) g
      WHERE t.id = $1::uuid
      """,
      [Ecto.UUID.dump!(id), n],
      timeout: :infinity
    )
  end

  t0 = System.monotonic_time(:millisecond)
  clone.("pages", page.id, pages_n - 1, %{})
  clone.("pages", page.id, drafts_n, %{
    "state" => "'draft'",
    "title" => "'Draft ' || g",
    "slug" => "'r6-draft-' || g"
  })
  clone.("posts", post.id, posts_n - 1, %{})

  # Every post gets `edges_n` distinct pages, drafts included in proportion;
  # the first `fat_n` posts get `fat_edges`.
  Repo.query!(
    """
    WITH pg AS (
      SELECT id, row_number() OVER (ORDER BY id) - 1 AS n, count(*) OVER () AS total
      FROM pages WHERE org_id = $1::uuid
    ), p AS (
      SELECT id, row_number() OVER (ORDER BY id) - 1 AS n FROM posts WHERE org_id = $1::uuid
    ), k AS (
      SELECT p.id AS source_id, p.n, g AS position
      FROM p, generate_series(0, $4 - 1) g
      WHERE g < CASE WHEN p.n < $3 THEN $4 ELSE $2 END
    )
    INSERT INTO content_links (org_id, source_id, target_id, kind, position, field, source_type, target_type)
    SELECT $1::uuid, k.source_id, pg.id, 'reference', k.position, 'ingredients', 'post', 'page'
    FROM k JOIN pg ON pg.n = (k.n * 7919 + k.position * 31) % pg.total
    ON CONFLICT DO NOTHING
    """,
    [Ecto.UUID.dump!(org), edges_n, fat_n, fat_edges],
    timeout: :infinity
  )

  for table <- ~w(content_links pages posts),
      do: Repo.query!("ANALYZE #{table}", [], timeout: :infinity)
  IO.puts("seeded in #{System.monotonic_time(:millisecond) - t0} ms")
end

[[edge_total]] = Repo.query!("SELECT count(*) FROM content_links WHERE field = $1", [field]).rows

[[posts_total, pages_total]] =
  Repo.query!("SELECT (SELECT count(*) FROM posts), (SELECT count(*) FROM pages)", []).rows

IO.puts("#{posts_total} posts, #{pages_total} pages, #{edge_total} edges on #{inspect(field)}")

# A published page most posts do not hold, one they often do, and a draft.
[[rare]] =
  Repo.query!(
    """
    SELECT cl.target_id::text FROM content_links cl JOIN pages p ON p.id = cl.target_id
    WHERE cl.field = $1 AND p.state = 'published'
    GROUP BY cl.target_id ORDER BY count(*) ASC, cl.target_id LIMIT 1
    """,
    [field]
  ).rows

[[common, common2]] =
  Repo.query!(
    """
    SELECT (array_agg(target_id::text ORDER BY c DESC))[1], (array_agg(target_id::text ORDER BY c DESC))[2]
    FROM (
      SELECT cl.target_id, count(*) c FROM content_links cl JOIN pages p ON p.id = cl.target_id
      WHERE cl.field = $1 AND p.state = 'published' GROUP BY cl.target_id
    ) s
    """,
    [field]
  ).rows

[[draft]] =
  Repo.query!(
    """
    SELECT cl.target_id::text FROM content_links cl JOIN pages p ON p.id = cl.target_id
    WHERE cl.field = $1 AND p.state = 'draft' LIMIT 1
    """,
    [field]
  ).rows

# Capture the SQL of the next read so it can be EXPLAINed.
:telemetry.attach(
  "r6-capture",
  [:kiln_cms, :repo, :query],
  fn _event, _measurements, %{query: query, params: params}, _config ->
    if String.contains?(query, "content_links"), do: Process.put(:r6_sql, {query, params})
  end,
  nil
)

cases = [
  {"has (rare)", %{"has" => [rare]}},
  {"has (common)", %{"has" => [common]}},
  {"has_all (two common)", %{"has_all" => [common, common2]}},
  {"has_none (common)", %{"has_none" => [common]}},
  {"has (draft)", %{"has" => [draft]}},
  {"count gt 500 (fat lists)", %{"count" => %{"gt" => 500}}},
  {"count eq 25", %{"count" => 25}},
  {"count eq 0", %{"count" => 0}}
]

percentile = fn sorted, p -> Enum.at(sorted, min(length(sorted) - 1, trunc(p * length(sorted)))) end

IO.puts("\n| Filter | Reader | Rows (page of 25) | p50 ms | p95 ms | Plan ms |")
IO.puts("|---|---|---|---|---|---|")

for {label, condition} <- cases, {reader, actor} <- [{"anonymous", nil}, {"editor", editor}] do
  read = fn ->
    CMS.list_published_posts!(%{custom_filter: %{field => condition}},
      actor: actor,
      tenant: org,
      authorize?: false,
      page: [limit: 25]
    )
  end

  rows = length(read.().results)

  times =
    for _ <- 1..runs do
      {us, _} = :timer.tc(read)
      us / 1000
    end
    |> Enum.sort()

  {sql, params} = Process.get(:r6_sql)

  plan =
    Repo.query!("EXPLAIN (ANALYZE, FORMAT JSON) " <> sql, params, timeout: :infinity).rows
    |> List.flatten()
    |> hd()
    |> List.wrap()
    |> hd()

  if System.get_env("R6_PLANS") do
    IO.puts(
      Repo.query!("EXPLAIN (ANALYZE, BUFFERS) " <> sql, params).rows
      |> Enum.map_join("\n", &hd/1)
    )
  end

  IO.puts(
    "| #{label} | #{reader} | #{rows} | #{Float.round(percentile.(times, 0.5), 1)} | " <>
      "#{Float.round(percentile.(times, 0.95), 1)} | #{Float.round(plan["Execution Time"], 1)} |"
  )
end
