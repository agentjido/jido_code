[
  import_deps: [
    :phoenix
  ],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: [
    "{mix,.formatter,.credo}.exs",
    "{config,lib,test}/**/*.{heex,ex,exs}"
  ],
  line_length: 120
]
