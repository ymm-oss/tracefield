defmodule Tracefield.LLM.HumanTest do
  use ExUnit.Case

  alias Tracefield.LLM.Human

  test "pending file lifecycle converts human markdown to the JSON entry contract" do
    dir = tmp_dir()

    opts = [
      human: %{
        pending_dir: Path.join(dir, "pending"),
        actor_id: "HUMAN",
        stage: "refine",
        question_ids: ["e7"],
        approve_targets: ["e3", "e5"]
      }
    ]

    messages = [
      %{role: "system", content: "TRACEFIELD_AGENT_TURN"},
      %{role: "user", content: "PRESENTED ENTRIES:\nENTRY e7 author=ARCH text=確認"}
    ]

    assert {:error, :awaiting_human} = Human.complete(messages, opts)

    pending = Path.join([dir, "pending", "HUMAN-refine.md"])
    content = File.read!(pending)
    assert content =~ "## SYSTEM"
    assert content =~ "TRACEFIELD_AGENT_TURN"
    assert content =~ "## RESPONSE（この下に回答を書いてください）"

    assert {:error, :awaiting_human} = Human.complete(messages, opts)

    File.write!(
      pending,
      content <>
        """

        - 質問への回答です [e7]
        - 補足観察です [e3] [e5]
        APPROVE
        """
    )

    assert {:ok, json} = Human.complete(messages, opts)
    assert {:ok, %{"entries" => entries}} = Jason.decode(json)

    assert [
             %{"type" => "answer", "text" => "質問への回答です", "citations" => ["e7"]},
             %{"type" => "observation", "text" => "補足観察です", "citations" => ["e3", "e5"]},
             %{"type" => "decision", "text" => "要件を承認する", "citations" => ["e3", "e5"]}
           ] = entries

    refute File.exists?(pending)
    assert File.exists?(Path.join([dir, "pending", "done", "HUMAN-refine.md"]))
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "tracefield-human-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
