[
  import_deps: [
    :ash_oban,
    :oban,
    :ash_authentication,
    :ash_authentication_phoenix,
    :ash_state_machine,
    :ash_graphql,
    :absinthe,
    :ash_json_api,
    :ash_admin,
    :ash_phoenix,
    :ash_postgres,
    :ash,
    :reactor,
    :ecto,
    :ecto_sql,
    :phoenix
  ],
  subdirectories: ["priv/*/migrations"],
  plugins: [Absinthe.Formatter, Spark.Formatter, Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "*.{heex,ex,exs}",
    "{config,lib,test}/**/*.{heex,ex,exs}",
    "priv/*/seeds.exs",
    "projects/**/*.{heex,ex,exs}",
    # The plugin SDK and the fixture plugin built on it (#1909). Globbed here
    # rather than listed under `subdirectories`: their own .formatter.exs
    # `import_deps` resolve against *their* deps/, which the core's CI never
    # fetches. CI also runs `mix format --check-formatted` inside each, so the
    # two configurations must agree.
    "sdk/kiln_plugin/{lib,test,config}/**/*.{ex,exs}",
    "sdk/kiln_plugin/{mix,.formatter}.exs",
    "sdk/fixtures/*/{lib,config}/**/*.{ex,exs}",
    "sdk/fixtures/*/{mix,.formatter}.exs"
  ]
]
