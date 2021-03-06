defmodule Bunck.Mixfile do
  use Mix.Project

  def project do
    [app: :bunck,
     version: "0.1.5",
     build_path: "_build",
     config_path: "config/config.exs",
     deps_path: "deps",
     lockfile: "mix.lock",
     elixir: "~> 1.4 and >= 1.4.5",
     package: package(),
     description: "A productive Elixir client for the Bunq API",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [ mod: {Bunck, []},
      extra_applications: [:logger, :hackney, :crypto]]
  end

  defp package do
    [
      maintainers: ["Derek Kraan"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/zilverline/bunck"},
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # To depend on another app inside the umbrella:
  #
  #   {:my_app, in_umbrella: true}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      hackney: "~> 1.8",
      uuid: "~> 1.1",
      poison: "~> 2.0 or ~> 3.0",
      ex_doc: "~> 0.16",
    ]
  end
end
