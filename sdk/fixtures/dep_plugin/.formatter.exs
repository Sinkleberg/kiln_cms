# What a plugin's own formatter config looks like: the block DSL's
# no-parentheses calls come from kiln_plugin's exported formatter config.
[
  import_deps: [:kiln_plugin],
  inputs: ["{mix,.formatter}.exs", "{config,lib}/**/*.{ex,exs}"]
]
