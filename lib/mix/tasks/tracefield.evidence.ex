defmodule Mix.Tasks.Tracefield.Evidence do
  @moduledoc "Run the H7 Step B evidence-integration/audit process demo."
  use Mix.Task

  @shortdoc "Run Tracefield evidence process demo"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    opts = parse_args(args)
    result = Tracefield.Evidence.run_demo(opts)
    Mix.shell().info(Jason.encode!(result, pretty: true))
  end

  defp parse_args(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [
          adapter: :string
        ]
      )

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    adapter =
      case Keyword.get(opts, :adapter, "mock") do
        "mock" -> Tracefield.LLM.Mock
        other -> Mix.raise("invalid adapter #{inspect(other)}; evidence demo is deterministic")
      end

    [adapter: adapter]
  end
end
