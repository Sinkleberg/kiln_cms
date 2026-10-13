import Config

# Used only when this fixture is compiled on its own (CI's `plugin_sdk` job).
# Ash 3.34 refuses to compile a resource with a `:string` attribute until this
# is chosen, and every block is an embedded Ash resource; inside the core the
# core's config/config.exs sets the same value. A real plugin's own CI needs
# the same line.
config :ash, default_string_length_count: :codepoints
