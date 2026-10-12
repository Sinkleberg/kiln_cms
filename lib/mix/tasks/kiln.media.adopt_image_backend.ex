defmodule Mix.Tasks.Kiln.Media.AdoptImageBackend do
  @shortdoc "Hand the image backend the imported rows whose images it already holds (#1955)"

  @moduledoc """
  Adopts media rows imported by URL into the active image backend
  (`Kiln.ImageBackend`), so Kiln can derive, rotate, transform and delete
  them like any upload — see `KilnCMS.Media.Adoption`.

      mix kiln.media.adopt_image_backend --dry-run    # count, write nothing
      mix kiln.media.adopt_image_backend
      mix kiln.media.adopt_image_backend --org <uuid>

  Needs a backend selected (`config :kiln_cms, :image_backend`) and
  configured. Only rows with no stored file are considered, and only those
  whose URL the backend recognises as its own. Each adopted row gets a
  variant job on the `:media` queue, which reads its dimensions back from the
  backend; this task returns once they are enqueued.
  """

  use Mix.Task

  @switches [dry_run: :boolean, org: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _argv} = OptionParser.parse!(args, strict: @switches)
    Mix.Task.run("app.start")

    org_id = opts[:org] || KilnCMS.Accounts.default_org_id()
    dry_run? = opts[:dry_run] == true

    case KilnCMS.Media.Adoption.run(org_id, dry_run?: dry_run?) do
      {:ok, %{scanned: scanned, adopted: adopted, failed: failed}} ->
        verb = if dry_run?, do: "Would adopt", else: "Adopted"

        Mix.shell().info(
          "#{verb} #{adopted} of #{scanned} row(s) with no stored file in org #{org_id}" <>
            if(failed > 0, do: "; #{failed} refused (see the log)", else: "") <> "."
        )

      {:error, :no_active_backend} ->
        Mix.raise(
          "No image backend is active. Select one with `config :kiln_cms, :image_backend, " <>
            "Module` and give it its settings; `mix kiln.plugins.doctor` checks the selection."
        )
    end
  end
end
