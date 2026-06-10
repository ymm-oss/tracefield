defmodule Mix.Tasks.Tracefield.Transfer do
  @moduledoc "Move a Tracefield agent between cluster directories."
  use Mix.Task

  alias Tracefield.{Reference, Transfer}

  @shortdoc "Transfer an agent between clusters"

  @impl true
  def run(args) do
    Mix.Task.run("app.start")

    args
    |> parse_args()
    |> run_transfer()
  end

  defp parse_args(args) do
    {opts, _rest, invalid} =
      OptionParser.parse(args,
        strict: [
          from: :string,
          to: :string,
          agent: :string,
          policy: :string,
          demo: :boolean
        ]
      )

    if invalid != [], do: Mix.raise("invalid options: #{inspect(invalid)}")
    opts
  end

  defp run_transfer(opts) do
    if Keyword.get(opts, :demo) do
      run_demo()
    else
      from = required!(opts, :from)
      to = required!(opts, :to)
      agent = required!(opts, :agent)
      policy = Keyword.get(opts, :policy, "distill")

      case Transfer.move(from, to, agent, policy: policy) do
        {:error, reason} -> Mix.raise("transfer failed: #{inspect(reason)}")
        result -> print_result(result)
      end
    end
  end

  defp run_demo do
    base =
      Path.join(System.tmp_dir!(), "tracefield-transfer-#{System.unique_integer([:positive])}")

    a = Path.join(base, "A")
    b = Path.join(base, "B")
    setup_demo!(a, b)

    Mix.shell().info("tracefield.transfer demo")
    Mix.shell().info("clusters: A=#{a} B=#{b}")
    Mix.shell().info("")
    Mix.shell().info("1. A: agent X has 4 memory lines; 1 cites a retracted A store entry")

    result = Transfer.move(a, b, "X", policy: :distill)

    Mix.shell().info("2. stale exclusion: #{result.stale_excluded}")
    Mix.shell().info("3. B store summary with provenance")
    print_store(Path.join(b, "store.jsonl"))
    Mix.shell().info("4. B agents.json")
    Mix.shell().info(File.read!(Path.join(b, "agents.json")) |> String.trim_trailing())
    Mix.shell().info("5. A agents.json and departure record")
    Mix.shell().info(File.read!(Path.join(a, "agents.json")) |> String.trim_trailing())
    print_store(Path.join(a, "store.jsonl"))
  end

  defp setup_demo!(a, b) do
    File.mkdir_p!(Path.join(a, "private"))
    File.mkdir_p!(Path.join(b, "private"))
    File.mkdir_p!(Path.join(a, "memory"))
    File.write!(Path.join(a, "task.md"), "A task\n")
    File.write!(Path.join(b, "task.md"), "B task\n")
    File.write!(Path.join(a, "procedure-x.md"), "X procedure\n")
    File.write!(Path.join([a, "private", "x.md"]), "X private doc stays in A\n")

    File.write!(
      Path.join(a, "agents.json"),
      Jason.encode!(
        [
          %{
            id: "X",
            domain: "x",
            desc: "transfer demo",
            private_doc: "x.md",
            model: "model-x",
            procedure: "procedure-x.md"
          }
        ], pretty: true) <> "\n"
    )

    File.write!(Path.join(b, "agents.json"), Jason.encode!([], pretty: true) <> "\n")

    {:ok, ref} = Reference.start_link(persist_path: Path.join(a, "store.jsonl"))
    [active] = Reference.absorb(ref, [%{type: :observation, text: "active source"}], "A")
    [stale] = Reference.absorb(ref, [%{type: :observation, text: "retracted source"}], "A")
    Reference.retract(ref, stale.id)
    GenServer.stop(ref)

    memory =
      [
        memory_line("valid from active citation", [active.id]),
        memory_line("stale from retracted citation", [stale.id]),
        memory_line("valid from unknown citation", ["unknown-e99"]),
        memory_line("valid without citation", [])
      ]
      |> Enum.join()

    File.write!(Path.join([a, "memory", "X.jsonl"]), memory)
  end

  defp print_result(result) do
    Mix.shell().info("policy: #{result.policy}")
    Mix.shell().info("stale_excluded: #{result.stale_excluded}")

    Mix.shell().info(
      "summary_entry: #{if(result.summary_entry, do: result.summary_entry.id, else: "-")}"
    )

    Mix.shell().info("files:")
    Enum.each(result.files, &Mix.shell().info("- #{&1}"))
  end

  defp print_store(path) do
    {:ok, ref} = Reference.start_link(persist_path: path)

    Enum.each(Reference.all(ref), fn entry ->
      transfer_from =
        Map.get(entry.meta, :transfer_from, Map.get(entry.meta, "transfer_from", "-"))

      agent = Map.get(entry.meta, :agent, Map.get(entry.meta, "agent", "-"))

      Mix.shell().info(
        "#{entry.id} status=#{entry.status} author=#{entry.author} transfer_from=#{transfer_from} agent=#{agent} text=#{entry.text}"
      )
    end)

    GenServer.stop(ref)
  end

  defp required!(opts, key) do
    Keyword.get(opts, key) ||
      Mix.raise("missing required --#{String.replace(to_string(key), "_", "-")}")
  end

  defp memory_line(text, citations) do
    Jason.encode!(%{
      ts: "2026-06-10T00:00:00Z",
      mode: "converge",
      text: text,
      citations: citations
    }) <> "\n"
  end
end
