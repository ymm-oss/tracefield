defmodule Tracefield.MixProject do
  use Mix.Project

  @source_url "https://github.com/ryoichi-izumita/tracefield"

  def project do
    [
      app: :tracefield,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "tracefield",
      description: description(),
      package: package(),
      source_url: @source_url,
      docs: docs()
    ]
  end

  defp description do
    "Governable exploration for multi-agent systems: a research harness for " <>
      "semi-soluble orchestration, keeping the downstream influence of every " <>
      "input traceable, isolable, and retractable."
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      maintainers: ["Ryoichi Izumita"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Tracefield.Application, []}
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:jido, "~> 2.3"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
