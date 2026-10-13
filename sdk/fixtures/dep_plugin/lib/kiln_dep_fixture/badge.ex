defmodule KilnDepFixture.Badge do
  @moduledoc "A block contributed by a plugin compiled as a dependency."
  use Kiln.Block

  block :dep_badge do
    field :label, :string, required: true
  end

  @impl Kiln.Block.Renderer
  def render(block, :json), do: %{"_type" => "dep_badge", "label" => block.label}
  def render(_block, _surface), do: nil

  @impl Kiln.Block.Renderer
  def search_text(block), do: block.label || ""
end
