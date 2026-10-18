defmodule KilnCMSWeb.ComputedBuilder do
  @moduledoc """
  State behind the computed-field formula builder on `/editor/fields`
  (`KilnCMSWeb.ComputedBuilderComponents`): which view the admin is in, the
  recipe they picked and its slots, and the document the preview runs on.

  The builder adds no storage. It sits in front of the definition's one
  `compute` attribute: on every change event, `apply_params/2` takes the
  `builder` params the form submitted, writes the recipe's formula into
  `compute` when the admin is in the recipe view, and strips the builder's own
  params before they reach the resource. In the formula view `compute` is
  whatever the admin typed. Either way, the formula the resource validates and
  stores is the only thing that persists — the recipe is re-recognized from it
  (`KilnCMS.CMS.Computed.Recipes.recognize/1`) when the field is edited again.

  ## Views

    * `"recipe"` — the macro builder: pick a recipe, fill its slots;
    * `"formula"` — the code builder: write the template, with value and
      function palettes and a live preview.

  Switching recipe → formula keeps the generated formula, so a recipe is a
  starting point for a hand-written formula. Switching formula → recipe
  recognizes the formula when it is a recipe's; when it isn't, no recipe is
  picked and the typed formula is kept (and saved) until one is.
  """
  alias KilnCMS.CMS.Computed
  alias KilnCMS.CMS.Computed.Recipes

  @type t :: %{
          mode: String.t(),
          recipe: String.t() | nil,
          slots: %{String.t() => String.t()},
          error: String.t() | nil,
          pending: String.t() | nil,
          sample: String.t() | nil,
          unmatched?: boolean()
        }

  @doc """
  The builder for a stored formula: the recipe view when the formula is a
  recipe's (or there is none yet), the formula view otherwise.
  """
  @spec new(String.t() | nil) :: t()
  def new(compute \\ nil) do
    case Recipes.recognize(compute) do
      {:ok, id, slots} -> state("recipe", id, slots)
      :error when compute in [nil, ""] -> state("recipe", nil, %{})
      :error -> state("formula", nil, %{})
    end
  end

  defp state(mode, recipe, slots),
    do: %{
      mode: mode,
      recipe: recipe,
      slots: slots,
      error: nil,
      pending: nil,
      sample: nil,
      unmatched?: false
    }

  @doc """
  Fold the form's `builder` params into the builder and into `compute`.
  Returns the params as the resource should see them (no `builder` key) and
  the updated builder.
  """
  @spec apply_params(map(), t()) :: {map(), t()}
  def apply_params(params, builder) do
    {submitted, params} = Map.pop(params, "builder")
    submitted = if is_map(submitted), do: submitted, else: %{}

    if params["field_type"] in [nil, "computed"] do
      builder
      |> Map.put(:sample, blank_to_nil(submitted["sample"]) || builder.sample)
      |> next(submitted, params)
    else
      {params, builder}
    end
  end

  # Formula → recipe: recognize what was typed.
  defp next(%{mode: "formula"} = builder, %{"mode" => "recipe"}, params) do
    case Recipes.recognize(params["compute"]) do
      {:ok, id, slots} ->
        {params,
         %{
           builder
           | mode: "recipe",
             recipe: id,
             slots: slots,
             error: nil,
             pending: nil,
             unmatched?: false
         }}

      :error ->
        unmatched? = not blank?(params["compute"])

        {params,
         %{
           builder
           | mode: "recipe",
             recipe: nil,
             slots: %{},
             error: nil,
             pending: nil,
             unmatched?: unmatched?
         }}
    end
  end

  # Recipe → formula: keep the formula the recipe wrote.
  defp next(%{mode: "recipe"} = builder, %{"mode" => "formula"}, params),
    do: {params, %{builder | mode: "formula", error: nil, pending: nil, unmatched?: false}}

  defp next(%{mode: "recipe"} = builder, submitted, params) do
    recipe = blank_to_nil(submitted["recipe"]) || builder.recipe

    slots =
      if recipe == builder.recipe,
        do: Map.merge(builder.slots, stringify(submitted["slots"])),
        else: Recipes.defaults(recipe)

    builder = %{builder | recipe: recipe, slots: slots}

    # No recipe picked yet: whatever formula is already there stays.
    if is_nil(recipe), do: {params, builder}, else: write(recipe, params, builder)
  end

  defp next(builder, _submitted, params), do: {params, builder}

  defp write(recipe, params, builder) do
    with nil <- Recipes.missing(recipe, builder.slots),
         {:ok, formula} <- Recipes.build(recipe, builder.slots) do
      {Map.put(params, "compute", keep_if_same(params["compute"], formula)),
       %{builder | error: nil, pending: nil, unmatched?: false}}
    else
      # A blank still to fill: a prompt, not an error — a recipe just picked has
      # nothing in its blanks yet. The formula is blanked either way, so the
      # definition can't be saved with the last formula that *did* build.
      prompt when is_binary(prompt) ->
        {Map.put(params, "compute", ""),
         %{builder | error: nil, pending: prompt, unmatched?: false}}

      {:error, message} ->
        {Map.put(params, "compute", ""),
         %{builder | error: message, pending: nil, unmatched?: false}}
    end
  end

  # A stored formula the recipe view recognized can differ from the recipe's
  # own output in spacing inside `{{ }}` or in quote marks — the same template,
  # written differently. Keep the admin's text unless the recipe now means
  # something else, so editing a field's label doesn't rewrite its formula.
  defp keep_if_same(current, formula) do
    with true <- is_binary(current),
         {:ok, template} <- Computed.parse(current),
         {:ok, ^template} <- Computed.parse(formula) do
      current
    else
      _ -> formula
    end
  end

  @doc """
  What the preview shows for `compute` against a sample context: `{:ok,
  value}`, `:blank` when the formula evaluates to nothing, `{:error, message}`
  when it doesn't parse, or `{:failed, message}` when it parses and then fails
  on this document — which the save would quietly store as blank.
  """
  @spec preview(String.t() | nil, map()) ::
          {:ok, term()} | :blank | {:error, String.t()} | {:failed, String.t()} | nil
  def preview(compute, context) do
    if blank?(compute) do
      nil
    else
      case Computed.evaluate_checked(compute, context) do
        {:ok, nil} -> :blank
        {:ok, value} -> {:ok, value}
        {:error, {:parse, message}} -> {:error, message}
        {:error, {:raised, message}} -> {:failed, message}
      end
    end
  end

  defp stringify(slots) when is_map(slots),
    do: Map.new(slots, fn {k, v} -> {to_string(k), to_string(v)} end)

  defp stringify(_slots), do: %{}

  defp blank?(value), do: value in [nil, ""] or (is_binary(value) and String.trim(value) == "")
  defp blank_to_nil(value), do: if(blank?(value), do: nil, else: value)
end
