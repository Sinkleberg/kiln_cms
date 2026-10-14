defmodule Mix.Tasks.Kiln.Plugins.DoctorUnloadedTest do
  @moduledoc """
  The doctor's image-backend check on a plugin that is compiled but not loaded
  yet: what a plugin's own test sees on a fresh VM, where nothing else has
  touched its entry module. `function_exported?/3` is false for an unloaded
  module, so without loading it first the check reported the plugin's backend
  as undeclared (kiln_cloudflare_images' CI, 10-14).
  """
  # async: false — it adds to the global code path.
  use ExUnit.Case, async: false

  alias Mix.Tasks.Kiln.Plugins.Doctor

  @moduletag :tmp_dir

  test "a plugin that isn't loaded yet still declares its image backend", %{tmp_dir: dir} do
    n = System.unique_integer([:positive])
    plugin = Module.concat(["DoctorUnloaded#{n}", "Plugin"])

    [{^plugin, beam}] =
      Code.compile_string("""
      defmodule #{inspect(plugin)} do
        use Kiln.Plugin
        def image_backends, do: [KilnCMS.FixturePlugin.ImageBackend]
      end
      """)

    # Leave it loadable from disk, but not loaded.
    File.write!(Path.join(dir, "#{plugin}.beam"), beam)
    true = :code.add_patha(String.to_charlist(dir))
    on_exit(fn -> :code.del_path(String.to_charlist(dir)) end)
    :code.purge(plugin)
    :code.delete(plugin)
    refute :code.is_loaded(plugin)

    assert Doctor.image_backend_problems([plugin], KilnCMS.FixturePlugin.ImageBackend) == []
  end
end
