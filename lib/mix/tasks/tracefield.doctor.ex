defmodule Mix.Tasks.Tracefield.Doctor do
  @shortdoc "Check the environment: toolchain, Ollama, API keys, CLI adapters"

  @moduledoc """
  Diagnose whether your environment is ready to run tracefield, and which model
  adapters are available.

      mix tracefield.doctor

  It never fails the build — it just reports. `mock` always works (no model
  needed); the other adapters depend on what it finds here.
  """
  use Mix.Task

  @ollama_url "http://localhost:11434/api/tags"

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:req)

    Mix.shell().info(IO.ANSI.format([:bright, "tracefield doctor", :reset]) |> to_string())
    Mix.shell().info("")

    section("Toolchain")
    ok("Elixir #{System.version()}")
    ok("Erlang/OTP #{:erlang.system_info(:otp_release)}")

    section("Adapters")
    ok("mock — always available (synthetic output, no model)")

    ollama = check_ollama()
    openrouter = check_openrouter()
    cli = check_cli()

    section("Summary")
    Mix.shell().info("  ready adapters: #{ready_list(ollama, openrouter, cli)}")
    Mix.shell().info("  run a no-model smoke check:  mix tracefield.phase1 --adapter mock --n 4")
  end

  defp check_ollama do
    case safe_get(@ollama_url) do
      {:ok, %{status: 200, body: body}} ->
        models = body |> models_from_tags() |> Enum.take(8)

        ok("ollama — reachable at localhost:11434")

        if models == [] do
          note("no models pulled yet, e.g. `ollama pull gemma4:12b`")
        else
          note("models: #{Enum.join(models, ", ")}")
        end

        true

      _ ->
        fail("ollama — not reachable at localhost:11434")

        note(
          "start it with `ollama serve`, then `ollama pull <model>` (only needed for --adapter ollama)"
        )

        false
    end
  end

  defp check_openrouter do
    case System.get_env("OPENROUTER_API_KEY") do
      key when is_binary(key) and key != "" ->
        ok("openrouter — OPENROUTER_API_KEY set (#{mask(key)})")
        true

      _ ->
        fail("openrouter — OPENROUTER_API_KEY not set")

        note(
          "export OPENROUTER_API_KEY=... for cross-family runs (only needed for --adapter openrouter)"
        )

        false
    end
  end

  defp check_cli do
    claude = System.find_executable("claude")
    cursor = System.find_executable("cursor-agent")

    cond do
      claude || cursor ->
        found = [claude && "claude", cursor && "cursor-agent"] |> Enum.filter(& &1)
        ok("cli — found: #{Enum.join(found, ", ")}")
        true

      true ->
        fail("cli — neither `claude` nor `cursor-agent` on PATH")
        note("install one for --adapter cli (strong-model deliberation/synthesis)")
        false
    end
  end

  defp ready_list(ollama, openrouter, cli) do
    [
      "mock",
      ollama && "ollama",
      openrouter && "openrouter",
      cli && "cli"
    ]
    |> Enum.filter(& &1)
    |> Enum.join(", ")
  end

  # --- low-level helpers ------------------------------------------------------

  defp safe_get(url) do
    Req.get(url, receive_timeout: 1500, retry: false)
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp models_from_tags(%{"models" => models}) when is_list(models) do
    Enum.map(models, fn m -> Map.get(m, "name", "?") end)
  end

  defp models_from_tags(_), do: []

  defp mask(key) when byte_size(key) <= 8, do: "****"
  defp mask(key), do: String.slice(key, 0, 4) <> "…" <> String.slice(key, -4, 4)

  defp section(title),
    do: Mix.shell().info(IO.ANSI.format([:bright, title, :reset]) |> to_string())

  defp ok(msg), do: Mix.shell().info(IO.ANSI.format([:green, "  ✓ ", :reset, msg]) |> to_string())

  defp fail(msg),
    do: Mix.shell().info(IO.ANSI.format([:yellow, "  ✗ ", :reset, msg]) |> to_string())

  defp note(msg),
    do: Mix.shell().info(IO.ANSI.format([:faint, "      ↳ #{msg}", :reset]) |> to_string())
end
