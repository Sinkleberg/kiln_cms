# The block DSL's calls, exported so a plugin's own `.formatter.exs` can say
# `import_deps: [:kiln_plugin]` and format `block`/`field`/`migrate` the way
# the core does (no parentheses).
locals_without_parens = [block: 1, block: 2, field: 2, field: 3, migrate: 1, version: 1]

# `import_deps` so the DSL calls in tests format the way the core formats them.
# The core's own `mix format` also covers these files (see its
# `.formatter.exs`), under its broader `import_deps`; both checks run in CI and
# must agree.
[
  import_deps: [:ash, :spark],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
