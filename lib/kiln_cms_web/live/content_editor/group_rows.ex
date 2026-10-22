defmodule KilnCMSWeb.ContentEditor.GroupRows do
  @moduledoc """
  The content editor's wire form for a `:group` custom field (structured
  rows, `FieldDefinition.group_fields/1`).

  A group's inputs are named into its own key of `custom_fields`:

    * a single group posts one map, `…[<field>][<sub-field>]`;
    * a repeating group (`multiple`) posts one map per row, keyed by the row's
      position, `…[<field>][<index>][<sub-field>]`, which `normalize/2` turns
      into the ordered list `ApplyCustomFields` coerces.

  Two blank markers keep the shape whole. `…[<field>][_]` keeps the group in
  the params when nothing else would post — every row removed, or a single
  group whose only checkbox was cleared — since an absent group keeps its
  stored rows, the way an emptied gallery's blank `name[]` input does. And
  `…[<field>][<index>][_row]` keeps a row in place when none of its inputs
  posts (a row of cleared checkboxes). Both are dropped here, together with
  LiveView's `_unused_…` companions: every key starting with `_`, which no
  sub-field name can (`FieldDefinition` names start with a letter).

  Rows carry no identity, so they are addressed by position — the position
  `ApplyCustomFields` reports a problem under (`dosages[2].unit`), since a
  blank row is posted and counted like any other until a save drops it.
  """

  @doc """
  Fold each repeating group's posted rows (a map keyed by position) into a
  list, in order, and drop the blank markers from every group's rows. Lists,
  other fields and absent groups pass through untouched.
  """
  @spec normalize(map(), [map()]) :: map()
  def normalize(%{"custom_fields" => %{} = custom} = params, definitions) do
    custom =
      Enum.reduce(definitions, custom, fn
        %{field_type: :group, name: name} = definition, custom ->
          case custom do
            %{^name => value} -> Map.put(custom, name, normalize_value(value, definition))
            _absent -> custom
          end

        _other, custom ->
          custom
      end)

    Map.put(params, "custom_fields", custom)
  end

  def normalize(params, _definitions), do: params

  defp normalize_value(%{} = posted, %{multiple: true}) when not is_struct(posted) do
    posted
    |> Enum.flat_map(fn {key, row} ->
      case Integer.parse(to_string(key)) do
        {index, ""} -> [{index, clean_row(row)}]
        _marker -> []
      end
    end)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end

  defp normalize_value(rows, %{multiple: true}) when is_list(rows),
    do: Enum.map(rows, &clean_row/1)

  defp normalize_value(%{} = row, _single) when not is_struct(row), do: clean_row(row)
  defp normalize_value(value, _definition), do: value

  defp clean_row(%{} = row) when not is_struct(row),
    do: Map.reject(row, fn {key, _value} -> String.starts_with?(to_string(key), "_") end)

  defp clean_row(_row), do: %{}

  @doc """
  A group's value as the editor shows it: what was posted while the form
  holds it — rows a save would drop as blank included — else the stored
  value.
  """
  @spec posted(Phoenix.HTML.Form.t() | AshPhoenix.Form.t(), String.t()) :: term()
  def posted(form, name) do
    case AshPhoenix.Form.params(form) do
      %{"custom_fields" => %{^name => posted}} -> posted
      _not_posted -> KilnCMSWeb.ContentEditor.Shared.custom_field_value(form, name)
    end
  end

  @doc """
  The rows a repeating group shows, from a stored value or posted params: a
  list as it is (a non-map entry as an empty row), a lone object (stored
  while the group was single) as one row, anything else as none.
  """
  @spec rows(term()) :: [map()]
  def rows(rows) when is_list(rows), do: Enum.map(rows, &clean_row/1)
  def rows(%{} = row) when not is_struct(row) and map_size(row) > 0, do: [clean_row(row)]
  def rows(_none), do: []

  @doc """
  The one object a single group shows: the value itself, or the first row of
  a list (stored while the group was `multiple` — the row saving keeps).
  """
  @spec row(term()) :: map()
  def row(value), do: value |> rows() |> List.first(%{})

  @doc "One more, blank row at the end — unless the group is full (`max_items`)."
  @spec add([map()], map()) :: [map()]
  def add(rows, definition) do
    if full?(rows, definition), do: rows, else: rows ++ [%{}]
  end

  @doc "The rows without the one at `index`; an index out of range changes nothing."
  @spec remove([map()], integer()) :: [map()]
  def remove(rows, index) when index >= 0 and index < length(rows),
    do: List.delete_at(rows, index)

  def remove(rows, _index), do: rows

  @doc "The row at `index` swapped with its neighbour above (`\"up\"`) or below."
  @spec move([map()], integer(), String.t()) :: [map()]
  def move(rows, index, dir) do
    other = if dir == "up", do: index - 1, else: index + 1

    if index in 0..(length(rows) - 1)//1 and other in 0..(length(rows) - 1)//1 do
      rows
      |> List.replace_at(index, Enum.at(rows, other))
      |> List.replace_at(other, Enum.at(rows, index))
    else
      rows
    end
  end

  @doc """
  The rows in a dragged order: the old positions, each once. Anything that is
  not exactly a permutation of the rows — a stale page, a hand-made event —
  changes nothing, so a drag can reorder rows but never drop or copy one.
  """
  @spec reorder([map()], [term()]) :: [map()]
  def reorder(rows, order) when is_list(order) do
    positions = Enum.map(order, &position/1)

    if Enum.sort(positions) == Enum.to_list(0..(length(rows) - 1)//1),
      do: Enum.map(positions, &Enum.at(rows, &1)),
      else: rows
  end

  def reorder(rows, _order), do: rows

  defp position(value) when is_integer(value), do: value

  defp position(value) when is_binary(value) do
    case Integer.parse(value) do
      {index, ""} -> index
      _other -> nil
    end
  end

  defp position(_value), do: nil

  @doc "Whether a repeating group already holds `max_items` rows."
  @spec full?([map()], map()) :: boolean()
  def full?(rows, %{max_items: max}) when is_integer(max), do: length(rows) >= max
  def full?(_rows, _definition), do: false

  @doc "Whether removing a row would take a repeating group below `min_items`."
  @spec at_minimum?([map()], map()) :: boolean()
  def at_minimum?(rows, %{min_items: min}) when is_integer(min), do: length(rows) <= min
  def at_minimum?(_rows, _definition), do: false

  @doc """
  The repeating groups whose posted rows include a blank one, as
  `%{name => rows}` — what an autosave would otherwise take off the screen.
  A save drops a blank row (`ApplyCustomFields`) and the form is rebuilt from
  the saved record, so a row the writer just added, and has not typed into
  yet, would vanish two seconds later. The editor validates these back onto
  the rebuilt form.
  """
  @spec pending(map(), [map()]) :: map()
  def pending(%{"custom_fields" => %{} = custom}, definitions) do
    for %{field_type: :group, multiple: true, name: name} <- definitions,
        rows = Map.get(custom, name),
        is_list(rows) and Enum.any?(rows, &blank_row?/1),
        into: %{},
        do: {name, rows}
  end

  def pending(_params, _definitions), do: %{}

  defp blank_row?(%{} = row),
    do: Enum.all?(row, fn {_key, value} -> String.trim(to_string(value)) == "" end)

  defp blank_row?(_row), do: true

  @doc """
  A group's validation messages sorted by where they belong, from the path
  each names (`Unit (dosages[2].unit) is required`):

    * `:cells` — `%{{index, sub_name} => [message]}` for a sub-field of a row
      (`index` is `nil` on a single group), the message without its path;
    * `:rows` — `%{index => [message]}` for a whole row;
    * `:field` — everything else (the group's own "is required", a row
      count outside `min_items`/`max_items`), as given.
  """
  @spec errors([String.t()], String.t()) :: %{cells: map(), rows: map(), field: [String.t()]}
  def errors(messages, name) do
    pattern =
      ~r/\A(?<label>.*?) \(#{Regex.escape(name)}(?:\[(?<index>\d+)\])?(?:\.(?<sub>[a-z][a-z0-9_]*))?\) (?<message>.*)\z/s

    Enum.reduce(messages, %{cells: %{}, rows: %{}, field: []}, fn message, acc ->
      case Regex.named_captures(pattern, message) do
        %{"sub" => sub, "index" => index, "label" => label, "message" => text} when sub != "" ->
          key = {parse_index(index), sub}

          %{
            acc
            | cells:
                Map.update(acc.cells, key, ["#{label} #{text}"], &(&1 ++ ["#{label} #{text}"]))
          }

        %{"index" => index, "message" => text} when index != "" ->
          i = parse_index(index)
          %{acc | rows: Map.update(acc.rows, i, [text], &(&1 ++ [text]))}

        _field ->
          %{acc | field: acc.field ++ [message]}
      end
    end)
  end

  defp parse_index(""), do: nil
  defp parse_index(index), do: String.to_integer(index)
end
