defmodule Tracefield.MixProject do
  use Mix.Project

  def project do
    [
      app: :tracefield,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
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
      {:jido, "~> 2.3"}
    ]
  end
end
