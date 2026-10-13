import Config

# Only for building and testing this package on its own. A dependency's config
# never reaches the project that uses it: inside a KilnCMS build the core's
# config/config.exs is what applies (and sets the same value).
#
# Ash 3.34 refuses to compile a resource with a `:string` attribute until this
# is chosen, and every block is an embedded Ash resource. `:codepoints` is the
# core's choice, so a block behaves the same here as in the core.
config :ash, default_string_length_count: :codepoints
