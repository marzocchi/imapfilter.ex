defmodule Imap.MixProject do
  use Mix.Project

  def project do
    [
      app: :imapfilter,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: [test: "test --no-start"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :ssl, :gen_smtp],
      mod: {ImapFilter.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:gen_stage, "~> 1.0.0"},
      {:gen_smtp, "~> 1.1.1"},
      {:castore, "~> 0.1.0"},
      {:yaml_elixir, "~> 2.8.0"},
      {:uuid, "~> 1.1", only: [:test], runtime: false},
      {:credo_naming, "~> 2.0", only: [:dev, :test], runtime: false},
    ]
  end
end
