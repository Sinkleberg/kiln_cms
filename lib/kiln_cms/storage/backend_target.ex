defmodule KilnCMS.Storage.BackendTarget do
  @moduledoc """
  A resolved image backend (`Kiln.ImageBackend`, #1955), as one of the stores
  `KilnCMS.Storage` routes to — the third answer `KilnCMS.Storage.locate/1`
  can give, beside `nil` (the operator's store) and a site's `Profile`.

  `name` is what the item row records; `module` is what it resolved to.
  """

  @enforce_keys [:name, :module]
  defstruct [:name, :module]

  @type t :: %__MODULE__{name: String.t(), module: module()}

  @doc "The target for `module`, named the way rows record it."
  @spec for(module()) :: t()
  def for(module), do: %__MODULE__{name: module.name(), module: module}
end
