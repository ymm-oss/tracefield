defmodule Tracefield.QATest do
  use ExUnit.Case

  alias Tracefield.{LLM.Mock, QA}

  test "mock TRACEFIELD_QA returns matched true when prompt contains IMPLEMENTED" do
    messages = [
    %{
      role: "user",
      content: "TRACEFIELD_QA\nfiles: IMPLEMENTED.md\n実装変更: done"
    }
  ]

    assert {:ok, content} = Mock.complete(messages, [])
    assert %{"matched" => true, "note" => "mock突合"} = Jason.decode!(content)
  end

  test "mock TRACEFIELD_QA returns matched false when prompt lacks IMPLEMENTED" do
    messages = [
    %{
      role: "user",
      content: "TRACEFIELD_QA\nfiles: README.md\n実装変更: pending"
    }
  ]

    assert {:ok, content} = Mock.complete(messages, [])
    assert %{"matched" => false, "note" => "mock突合"} = Jason.decode!(content)
  end

  test "QA.judge falls back to test exit when adapter returns broken JSON" do
    defmodule BrokenAdapter do
    @behaviour Tracefield.LLM

      @impl true
      def complete(_messages, _opts), do: {:ok, "not json at all"}
    end

    requirement = %{id: "e10", text: "要件（受入基準: テスト green）"}
    change = %{text: "実装変更", meta: %{files: ["IMPLEMENTED.md"]}}

    assert %{matched: true, note: "judge unavailable"} =
             QA.judge(BrokenAdapter, [], requirement, change, %{exit: 0, tail: "ok"})

    assert %{matched: false, note: "judge unavailable"} =
             QA.judge(BrokenAdapter, [], requirement, change, %{exit: 1, tail: "fail"})
  end
end
