defmodule Tracefield.Phase1TaskTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  test "phase1 mock accepts contaminant b flag" do
    runs_existed? = File.dir?("runs")
    before = "runs/*" |> Path.wildcard() |> MapSet.new()

    on_exit(fn ->
      after_files = "runs/*" |> Path.wildcard() |> MapSet.new()

      after_files
      |> MapSet.difference(before)
      |> Enum.each(&File.rm/1)

      if not runs_existed? and File.dir?("runs") and File.ls!("runs") == [] do
        File.rmdir!("runs")
      end
    end)

    Mix.Task.reenable("tracefield.phase1")

    output =
      capture_io(fn ->
        Mix.Tasks.Tracefield.Phase1.run([
          "--adapter",
          "mock",
          "--n",
          "1",
          "--rounds",
          "1",
          "--contaminant",
          "b"
        ])
      end)

    assert output =~ "contaminant: b"
  end
end
