# Compiled with the package under MIX_ENV=test (`elixirc_paths/1` in mix.exs)
# rather than defined in the test file: they implement protocols, which are
# consolidated before the test files load.
defmodule Kiln.ContractTest.Note do
  @moduledoc false
  use Kiln.Block

  block :sdk_note do
    version(2)
    field :text, :string, required: true
    field :tone, :string, default: "info", editable_by: [:admin]

    migrate(from: 1, to: 2, fun: &__MODULE__.up/1)
  end

  def up(map), do: map

  @impl Kiln.Block.Renderer
  def render(block, :json), do: %{"_type" => "sdk_note", "text" => block.text}
  def render(_block, _surface), do: nil
end

defmodule Kiln.ContractTest.Plugin do
  @moduledoc false
  use Kiln.Plugin

  @impl Kiln.Plugin
  def blocks, do: [Kiln.ContractTest.Note]
end

defmodule Kiln.ContractTest.Stars do
  @moduledoc false
  use Kiln.FieldType

  @impl Kiln.FieldType
  def cast(value, _definition) when value in 1..5, do: {:ok, value}
  def cast(_value, _definition), do: {:error, "1 to 5"}
end

defmodule Kiln.ContractTest.Links do
  @moduledoc false
  use Kiln.Forms.SpamCheck

  @impl Kiln.Forms.SpamCheck
  def check(context) do
    if String.contains?(Kiln.Forms.SpamCheck.Context.text(context), "http"),
      do: flag(:link, 10),
      else: :ok
  end
end

defmodule Kiln.ContractTest.Backend do
  @moduledoc false
  use Kiln.ImageBackend

  @impl Kiln.ImageBackend
  def name, do: "sdk_test"
  @impl Kiln.ImageBackend
  def configured?, do: true
  @impl Kiln.ImageBackend
  def accepts?(_candidate), do: true
  @impl Kiln.ImageBackend
  def store(key, _path), do: {:ok, key}
  @impl Kiln.ImageBackend
  def fetch(_key), do: {:ok, ""}
  @impl Kiln.ImageBackend
  def delete(_key), do: :ok
  @impl Kiln.ImageBackend
  def url(key), do: "https://img.example/" <> key
end
