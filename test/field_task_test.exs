defmodule Tracefield.FieldTaskTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  test "field demo prints the live six-step story" do
    Mix.Task.reenable("tracefield.field")

    output =
      capture_io(fn ->
        Mix.Tasks.Tracefield.Field.run(["--demo"])
      end)

    assert output =~ "1. Field started"
    assert output =~ "2. A absorbed"
    assert output =~ "3. B discovered source=A/"
    assert output =~ "4. B absorbed decision"
    assert output =~ "5. A retracted"
    assert output =~ "6. Final B store"
    assert output =~ "status=retracted"
    assert output =~ "status=superseded"
    assert output =~ "source_chain: A/"
    assert output =~ "-> META/"
  end
end
