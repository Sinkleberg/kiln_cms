defmodule KilnDepFixture.Ribbon do
  @moduledoc """
  A block the plugin does NOT list in `blocks/0`. It exists so the
  recompile-edge check can add it and watch the core's registry pick it up.
  """
  use Kiln.Block

  block :dep_ribbon do
    field :text, :string
  end

  @impl Kiln.Block.Renderer
  def render(block, :json), do: %{"_type" => "dep_ribbon", "text" => block.text}
  def render(_block, _surface), do: nil

  @impl Kiln.Block.Renderer
  def search_text(block), do: block.text || ""
end
