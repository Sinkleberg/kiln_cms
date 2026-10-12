defmodule KilnCMS.Media.ImageBackendTest do
  @moduledoc """
  An image backend (#1955) end to end, against the fixture plugin's
  file-backed one (`KilnCMS.FixturePlugin.ImageBackend`):

    * **Which uploads it gets.** A stripped image bound for the operator's
      store, when the selected backend is configured and accepts it — and
      nothing else: not a document, not with no backend selected, not when it
      declines.
    * **Every later operation follows the row.** Fetch, delete, URL and ranged
      reads reach the backend through `KilnCMS.Storage` with the item, and a
      row whose backend is no longer installed fails rather than falling
      through to the operator's store.
    * **Variants are URLs.** The worker records the backend's rendering of the
      same labels, sizes and types the encoder would have written, unless the
      backend can't render them.
  """
  # async: false — the selected backend, its steering and Storage.Local all
  # live in the global app env.
  use KilnCMS.DataCase, async: false
  use Oban.Testing, repo: KilnCMS.Repo

  alias Kiln.ImageBackend.Registry
  alias KilnCMS.CMS
  alias KilnCMS.FixturePlugin.ImageBackend, as: Fixture
  alias KilnCMS.ImageProcessor
  alias KilnCMS.Media.{Ingest, Regeneration, VariantWorker}
  alias KilnCMS.Storage
  alias KilnCMS.Storage.BackendTarget

  setup do
    root = Path.join(System.tmp_dir!(), "kiln_ib_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    Application.put_env(:kiln_cms, KilnCMS.Storage.Local, root: root, base_url: "/uploads")

    on_exit(fn ->
      File.rm_rf!(root)
      Application.delete_env(:kiln_cms, KilnCMS.Storage.Local)
      Application.delete_env(:kiln_cms, :image_backend)
      Application.delete_env(:kiln_cms, :fixture_image_backend)
    end)

    %{root: root}
  end

  defp select_backend(opts \\ []) do
    Application.put_env(:kiln_cms, :image_backend, Fixture)
    Application.put_env(:kiln_cms, :fixture_image_backend, opts)
  end

  defp actor do
    Ash.Seed.seed!(KilnCMS.Accounts.User, %{
      email: "ib-#{System.unique_integer([:positive])}@example.com",
      hashed_password: Bcrypt.hash_pwd_salt("password123456"),
      confirmed_at: DateTime.utc_now(),
      role: :admin
    })
  end

  defp png(width, height) do
    path = Path.join(System.tmp_dir!(), "ib-#{System.unique_integer([:positive])}.png")
    {:ok, image} = Image.new(width, height, color: :green)
    {:ok, _} = Image.write(image, path)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp upload(path, name), do: Ingest.store_file(path, name, actor: actor())

  # A backend item as ingest leaves it: the file in the backend, the row naming it.
  defp backend_item(width, height) do
    key = "orig-#{System.unique_integer([:positive])}.png"
    {:ok, ^key} = Fixture.store(key, png(width, height))

    Ash.Seed.seed!(KilnCMS.CMS.MediaItem, %{
      filename: "orig.png",
      content_type: "image/png",
      storage_key: key,
      url: Fixture.url(key),
      image_backend: Fixture.name()
    })
  end

  describe "Registry" do
    test "nothing is active until the operator selects a backend" do
      assert Registry.active() == nil
      assert Fixture in Registry.installed()
    end

    test "a selected backend is active only while it reports itself configured" do
      select_backend()
      assert Registry.active() == Fixture

      select_backend(configured?: false)
      assert Registry.active() == nil
    end

    test "rows resolve by name, and an unknown name is not installed" do
      assert Registry.fetch("fixture_images") == {:ok, Fixture}
      assert Registry.fetch("gone_plugin") == {:error, :not_installed}
    end

    test "only the selected backend's hosts are allowed — even while it lacks settings" do
      assert Registry.csp_hosts() == []

      select_backend(configured?: false)
      assert Registry.csp_hosts() == ["https://images.fixture.test"]
    end
  end

  describe "ingest" do
    test "an image goes to the selected backend, and the row says so", %{root: root} do
      select_backend()

      assert {:ok, item} = upload(png(600, 400), "cat.png")

      assert item.image_backend == "fixture_images"
      assert item.storage_profile_id == nil
      assert item.url == "https://images.fixture.test/#{item.storage_key}/public"
      assert Fixture.stored?(item.storage_key)
      refute File.exists?(Path.join(root, item.storage_key))
    end

    test "with no backend selected, an image stays in the operator's store", %{root: root} do
      assert {:ok, item} = upload(png(600, 400), "cat.png")

      assert item.image_backend == nil
      assert File.exists?(Path.join(root, item.storage_key))
    end

    test "an image the backend declines stays in the operator's store", %{root: root} do
      select_backend(accepts?: false)

      assert {:ok, item} = upload(png(600, 400), "cat.png")

      assert item.image_backend == nil
      assert File.exists?(Path.join(root, item.storage_key))
    end

    test "a selected backend missing its settings is never offered the upload", %{root: root} do
      select_backend(configured?: false)

      assert {:ok, item} = upload(png(600, 400), "cat.png")

      assert item.image_backend == nil
      assert File.exists?(Path.join(root, item.storage_key))
    end

    test "a document never reaches it", %{root: root} do
      select_backend()
      path = Path.join(System.tmp_dir!(), "ib-#{System.unique_integer([:positive])}.txt")
      File.write!(path, "WEBVTT\n\n00:00.000 --> 00:01.000\nHello\n")
      on_exit(fn -> File.rm(path) end)

      assert {:ok, item} = Ingest.store_file(path, "captions.vtt", actor: actor())

      assert item.image_backend == nil
      assert File.exists?(Path.join(root, item.storage_key))
    end
  end

  describe "Storage follows the row" do
    test "fetch, URL and delete reach the backend" do
      item = backend_item(300, 200)

      assert {:ok, %BackendTarget{name: "fixture_images", module: Fixture}} = Storage.locate(item)
      assert {:ok, bytes} = Storage.fetch(item.storage_key, item)
      {:ok, image} = Image.from_binary(bytes)
      assert {Image.width(image), Image.height(image)} == {300, 200}

      {:ok, site} = Storage.locate(item)
      assert Storage.url(item.storage_key, site) == Fixture.url(item.storage_key)

      assert :ok = Storage.delete(item.storage_key, item)
      refute Fixture.stored?(item.storage_key)
    end

    test "ranged reads are sliced from the whole image, with the adapters' edges" do
      item = backend_item(50, 50)
      {:ok, whole} = Fixture.fetch(item.storage_key)
      total = byte_size(whole)

      assert {:ok, %{bytes: head, first: 0, last: 9, total: ^total}} =
               Storage.fetch_range(item.storage_key, 0, 9, item)

      assert head == binary_part(whole, 0, 10)

      assert {:ok, %{last: last}} = Storage.fetch_range(item.storage_key, 5, :eof, item)
      assert last == total - 1

      assert {:error, {:range_not_satisfiable, ^total}} =
               Storage.fetch_range(item.storage_key, total, :eof, item)

      dest = Path.join(System.tmp_dir!(), "ib-copy-#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm(dest) end)
      assert :ok = Storage.copy_to_file(item.storage_key, dest, at: item)
      assert File.read!(dest) == whole
    end

    test "a backend has no private storage" do
      item = backend_item(10, 10)

      refute Storage.private_available?(item)
      refute Storage.direct_uploads_available?(item)
      assert {:error, :private_unsupported} = Storage.fetch_private(item.storage_key, item)
      assert {:error, :private_unsupported} = Storage.store_private("k.png", "/dev/null", item)
    end

    test "a row whose backend is no longer installed fails, never falls back", %{root: root} do
      item = backend_item(10, 10)
      File.write!(Path.join(root, item.storage_key), "the operator's store must not answer")
      orphaned = %{item | image_backend: "uninstalled_plugin"}

      assert Storage.locate(orphaned) == {:error, {:image_backend, :not_installed}}

      assert Storage.fetch(item.storage_key, orphaned) ==
               {:error, {:image_backend, :not_installed}}
    end
  end

  describe "an edit" do
    # Nothing in `Media.Transform` knows about backends: it passes the item,
    # and the edited copy lands where the original is, under a new key.
    test "rotating writes the edited copy to the backend, keeping the original" do
      item = backend_item(300, 200)

      assert {:ok, rotated} =
               KilnCMS.Media.Transform.apply(item, :rotate_right, authorize?: false)

      assert {rotated.width, rotated.height} == {200, 300}
      assert rotated.storage_key != item.storage_key
      assert rotated.url == Fixture.url(rotated.storage_key)
      assert rotated.image_backend == "fixture_images"
      assert Fixture.stored?(rotated.storage_key)
      assert Fixture.stored?(item.storage_key)
    end
  end

  describe "VariantWorker" do
    defp job(item), do: %{media_item_id: item.id, org_id: item.org_id}

    test "records the backend's URLs for the labels the encoder would write" do
      item = backend_item(1200, 800)

      assert :ok = perform_job(VariantWorker, job(item))

      reloaded = CMS.get_media_item!(item.id, authorize?: false)
      assert {reloaded.width, reloaded.height} == {1200, 800}

      planned = ImageProcessor.plan(1200, 800, ".png", %{x: 0.5, y: 0.5})

      assert Map.keys(reloaded.variants) |> Enum.sort() ==
               planned |> Enum.map(& &1.label) |> Enum.sort()

      assert %{"url" => thumb_url, "width" => 400, "height" => 267, "content_type" => "image/png"} =
               reloaded.variants["thumb"]

      assert thumb_url == "https://images.fixture.test/#{item.storage_key}/w=400,h=267,f=png"
      assert reloaded.variants["card.webp"]["url"] =~ ",f=webp,trim="

      # No blob per variant, so nothing for a purge or a regeneration to delete…
      refute Enum.any?(reloaded.variants, fn {_label, entry} -> Map.has_key?(entry, "key") end)
      # …and a regeneration sweep agrees the item is done.
      assert Regeneration.current?(reloaded)
    end

    test "a backend that can't render keeps the encoder, storing each variant in the backend" do
      select_backend(renders?: false)
      item = backend_item(1200, 800)

      assert :ok = perform_job(VariantWorker, job(item))

      reloaded = CMS.get_media_item!(item.id, authorize?: false)
      assert %{"key" => thumb_key, "url" => thumb_url} = reloaded.variants["thumb"]
      assert Fixture.stored?(thumb_key)
      assert thumb_url == Fixture.url(thumb_key)
    end
  end

  describe "ImageProcessor.plan/4" do
    # The backend's map is only interchangeable with the encoder's if the two
    # agree on every label and size — a portrait source checks that the
    # responsive targets bound the LONGEST side, as `Image.thumbnail/2` does.
    for {w, h} <- [{1200, 800}, {800, 1600}, {900, 500}, {300, 200}] do
      test "names exactly what process/3 writes for a #{w}x#{h} source" do
        path = png(unquote(w), unquote(h))
        focal = %{x: 0.3, y: 0.7}

        {:ok, %{variants: written}} = ImageProcessor.process(path, ".png", focal)
        on_exit(fn -> Enum.each(written, &File.rm(&1.path)) end)

        planned = ImageProcessor.plan(unquote(w), unquote(h), ".png", focal)

        assert Enum.sort(for(v <- written, do: {v.label, v.width, v.height, v.content_type})) ==
                 Enum.sort(for(p <- planned, do: {p.label, p.width, p.height, p.content_type}))
      end
    end
  end
end
