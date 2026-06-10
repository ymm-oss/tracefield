defmodule Tracefield.BridgeTaskTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  test "bridge demo prints the cross-cluster retraction story" do
    Mix.Task.reenable("tracefield.bridge")

    output =
      capture_io(fn ->
        Mix.Tasks.Tracefield.Bridge.run(["--demo"])
      end)

    assert output =~ "1. クラスタA"
    assert output =~ "2. bridge"
    assert output =~ "3. クラスタB"
    assert output =~ "4. クラスタA"
    assert output =~ "5. --sync"
    assert output =~ "越境撤回:"
    assert output =~ "final B store state"
    assert output =~ "status=retracted"
    assert output =~ "status=superseded"
  end
end
