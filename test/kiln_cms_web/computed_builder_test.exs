defmodule KilnCMSWeb.ComputedBuilderTest do
  @moduledoc """
  The formula builder's state on its own: how the recipe and formula views
  write the one `compute` param, and what switching between them keeps.
  """
  use ExUnit.Case, async: true

  alias KilnCMSWeb.ComputedBuilder

  defp params(compute, builder),
    do: %{"field_type" => "computed", "compute" => compute, "builder" => builder}

  test "a new field starts in the recipe view; a stored formula opens where it fits" do
    assert %{mode: "recipe", recipe: nil} = ComputedBuilder.new()
    assert %{mode: "recipe", recipe: "slug"} = ComputedBuilder.new("{{ slugify(title) }}")
    assert %{mode: "formula"} = ComputedBuilder.new("{{ upcase(slugify(title)) }}")
  end

  test "the recipe view writes the formula and strips its own params" do
    {params, builder} =
      ComputedBuilder.apply_params(
        params("", %{"mode" => "recipe", "recipe" => "slug"}),
        ComputedBuilder.new()
      )

    assert params["compute"] == "{{ slugify(title) }}"
    refute Map.has_key?(params, "builder")
    assert builder.recipe == "slug"

    {params, _builder} =
      ComputedBuilder.apply_params(
        params("", %{"mode" => "recipe", "recipe" => "slug", "slots" => %{"source" => "excerpt"}}),
        builder
      )

    assert params["compute"] == "{{ slugify(excerpt) }}"
  end

  test "picking another recipe starts its slots from their defaults" do
    builder = ComputedBuilder.new("{{ slugify(excerpt) }}")

    {params, builder} =
      ComputedBuilder.apply_params(
        params("x", %{
          "mode" => "recipe",
          "recipe" => "reading_time",
          "slots" => %{"source" => "excerpt"}
        }),
        builder
      )

    assert params["compute"] == "{{ reading_time(body) }} min read"
    assert builder.slots["source"] == "body"
  end

  test "an empty blank is a prompt, not an error, and still blanks the formula" do
    {params, builder} =
      ComputedBuilder.apply_params(
        params("{{ slugify(title) }}", %{"mode" => "recipe", "recipe" => "multiply"}),
        ComputedBuilder.new()
      )

    assert params["compute"] == ""
    assert builder.error == nil
    assert builder.pending =~ "Pick a value"
  end

  test "a slot that can't build is an error and blanks the formula" do
    {params, builder} =
      ComputedBuilder.apply_params(
        params("", %{
          "mode" => "recipe",
          "recipe" => "label",
          "slots" => %{"value" => "title", "prefix" => "{{ body }}"}
        }),
        # Already on the label recipe: picking a recipe starts from its defaults.
        ComputedBuilder.new("{{ title }}")
      )

    assert params["compute"] == ""
    assert builder.error =~ "{{"
    assert builder.pending == nil
  end

  test "a recognized formula written differently is kept as the admin wrote it" do
    stored = "{{slugify( title )}}"
    builder = ComputedBuilder.new(stored)
    assert builder.recipe == "slug"

    # An unrelated change (the label) leaves the stored text alone…
    {params, _builder} =
      ComputedBuilder.apply_params(params(stored, %{"mode" => "recipe"}), builder)

    assert params["compute"] == stored

    # …and a change to the recipe's meaning writes the recipe's own form.
    {params, _builder} =
      ComputedBuilder.apply_params(
        params(stored, %{"mode" => "recipe", "slots" => %{"source" => "excerpt"}}),
        builder
      )

    assert params["compute"] == "{{ slugify(excerpt) }}"
  end

  test "recipe → formula keeps the generated formula; formula → recipe recognizes it" do
    builder = ComputedBuilder.new("{{ slugify(title) }}")

    {params, builder} =
      ComputedBuilder.apply_params(
        params("{{ slugify(title) }}", %{"mode" => "formula"}),
        builder
      )

    assert builder.mode == "formula"
    assert params["compute"] == "{{ slugify(title) }}"

    {_params, builder} =
      ComputedBuilder.apply_params(
        params("{{ word_count(body) }}", %{"mode" => "recipe"}),
        builder
      )

    assert %{mode: "recipe", recipe: "word_count", unmatched?: false} = builder
  end

  test "an unrecognized formula survives a switch to the recipe view until a recipe is picked" do
    builder = ComputedBuilder.new("{{ upcase(title) }}")

    {params, builder} =
      ComputedBuilder.apply_params(params("{{ upcase(title) }}", %{"mode" => "recipe"}), builder)

    assert %{mode: "recipe", recipe: nil, unmatched?: true} = builder
    assert params["compute"] == "{{ upcase(title) }}"
  end

  test "another field type passes through, without the builder's params" do
    {params, builder} =
      ComputedBuilder.apply_params(
        %{"field_type" => "string", "builder" => %{"mode" => "formula"}},
        ComputedBuilder.new()
      )

    assert params == %{"field_type" => "string"}
    assert builder.mode == "recipe"
  end

  test "the preview evaluates, reports a blank, or names the parse error" do
    context = %{document: %{"title" => "Hi There"}, fields: %{}}

    assert ComputedBuilder.preview("{{ slugify(title) }}", context) == {:ok, "hi-there"}
    assert ComputedBuilder.preview("{{ excerpt }}", context) == :blank

    assert {:error, "calls unknown function nope/0"} =
             ComputedBuilder.preview("{{ nope() }}", context)

    assert ComputedBuilder.preview("", context) == nil

    # Parses, then fails on this document: said so, not called empty.
    assert {:failed, message} =
             ComputedBuilder.preview(~s|{{ format_date("2026-01-01", "%H") }}|, context)

    assert message =~ "hour"
  end
end
