defmodule KilnCMSWeb.GraphqlDefaultOffset do
  @moduledoc """
  Defaults `offset` to `0` on offset-paginated GraphQL queries (#1883).

  An omitted `offset` means the first page, so `hasNextPage` must still be a
  boolean. Without this middleware it is not. The `:published` reads support
  both offset and keyset paging, and `config :ash, default_page_type: :keyset`
  makes Ash answer a page request with no `offset` as a keyset page.
  AshGraphql (1.12.0) renders a keyset page on an offset query's `PageOf*`
  type without `hasNextPage`, `hasPreviousPage`, `pageNumber` or `lastPage`.
  The non-null `hasNextPage` then nulls the whole field.

  Passing `offset: 0` explicitly asks Ash for an offset page, so this
  middleware fills it in before the AshGraphql resolver runs. It is installed
  as the schema's `action_middleware`, so it covers every query AshGraphql
  generates, including a project overlay's. It acts only on fields that
  declare an `offset` argument, which keyset and unpaginated queries do not.
  """
  @behaviour Absinthe.Middleware

  @impl true
  def call(%Absinthe.Resolution{state: :unresolved} = resolution, _config) do
    if offset_paginated?(resolution) and is_nil(resolution.arguments[:offset]) do
      %{resolution | arguments: Map.put(resolution.arguments, :offset, 0)}
    else
      resolution
    end
  end

  def call(resolution, _config), do: resolution

  defp offset_paginated?(%{definition: %{schema_node: %{args: args}}}) when is_map(args),
    do: Map.has_key?(args, :offset)

  defp offset_paginated?(_resolution), do: false
end
