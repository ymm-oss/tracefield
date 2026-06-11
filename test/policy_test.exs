defmodule Tracefield.PolicyTest do
  use ExUnit.Case, async: false

  alias Tracefield.Policy

  test "resolve applies priority, deep merge, and per-key provenance" do
    layers = [
      {:default, Policy.default_policy()},
      {:org, %{"coverage" => %{"threshold" => 0.3}, "git" => %{"base" => "trunk"}}},
      {:repo, %{"git" => %{"remote" => "upstream"}}},
      {:issue, %{"git" => %{"mode" => "branch"}}},
      {:cli, %{"coverage" => %{"mode" => "relative"}, "embed" => "ollama"}}
    ]

    {policy, sources} = Policy.resolve(layers)

    assert policy["coverage"]["mode"] == "relative"
    assert policy["coverage"]["threshold"] == 0.3
    assert policy["embed"] == "ollama"
    assert policy["recruit"] == false
    assert policy["git"]["mode"] == "branch"
    assert policy["git"]["base"] == "trunk"
    assert policy["git"]["remote"] == "upstream"
    assert policy["git"]["branch_template"] == "tracefield/{slug}"

    assert sources["coverage.mode"] == :cli
    assert sources["coverage.threshold"] == :org
    assert sources["embed"] == :cli
    assert sources["recruit"] == :default
    assert sources["git.mode"] == :issue
    assert sources["git.base"] == :org
    assert sources["git.remote"] == :repo
    assert sources["git.branch_template"] == :default
  end

  test "sharing_mode defaults to shared and rejects invalid values" do
  assert Policy.sharing_mode(Policy.default_policy(), "refine") == "shared"
  assert Policy.sharing_mode(Policy.default_policy(), "design") == "shared"

  policy = Map.put(Policy.default_policy(), "sharing", %{"refine" => "independent"})

  assert Policy.sharing_mode(policy, "refine") == "independent"
  assert Policy.sharing_mode(policy, "design") == "shared"

  assert_raise Mix.Error, ~r/invalid sharing\.refine "avoid"/, fn ->
    Policy.validate_top_keys!(%{"sharing" => %{"refine" => "avoid"}})
  end
  end

  test "sharing cascade resolves per stage with layer priority" do
    layers = [
      {:default, Policy.default_policy()},
      {:issue, %{"sharing" => %{"refine" => "independent", "design" => "combine"}}},
      {:cli, %{"sharing" => %{"design" => "shared"}}}
    ]

    {policy, sources} = Policy.resolve(layers)

    assert Policy.sharing_mode(policy, "refine") == "independent"
    assert Policy.sharing_mode(policy, "design") == "shared"
    assert sources["sharing.refine"] == :issue
    assert sources["sharing.design"] == :cli
  end

  test "resolve rejects unknown top-level keys" do
    assert_raise Mix.Error, ~r/unknown policy keys: typo/, fn ->
      Policy.resolve([{:default, Policy.default_policy()}, {:repo, %{"typo" => true}}])
    end
  end

  test "load_layers! returns default only when policy files are absent" do
    dir = tmp_dir()

    assert Policy.load_layers!(dir, %{}) == [{:default, Policy.default_policy()}]
  end

  test "load_layers! includes TRACEFIELD_ORG_POLICY when set" do
    dir = tmp_dir()
    org_policy = Path.join(dir, "org-policy.json")
    File.write!(org_policy, Jason.encode!(%{"coverage" => %{"threshold" => 0.4}}))

    previous = System.get_env("TRACEFIELD_ORG_POLICY")
    System.put_env("TRACEFIELD_ORG_POLICY", org_policy)

    on_exit(fn ->
      if previous do
        System.put_env("TRACEFIELD_ORG_POLICY", previous)
      else
        System.delete_env("TRACEFIELD_ORG_POLICY")
      end
    end)

    layers = Policy.load_layers!(dir, %{})

    assert {:org, %{"coverage" => %{"threshold" => 0.4}}} in layers
  end

  test "load_layers! reads workspace.json git as issue policy for compatibility" do
    dir = tmp_dir()
    File.mkdir_p!(Path.join(dir, "repo"))

    File.write!(
      Path.join(dir, "workspace.json"),
      Jason.encode!(%{
        "path" => "repo",
        "git" => %{"mode" => "branch", "base" => "main"}
      })
    )

    {policy, sources} =
      dir
      |> Policy.load_layers!(%{})
      |> Policy.resolve()

    assert policy["git"]["mode"] == "branch"
    assert policy["git"]["base"] == "main"
    assert sources["git.mode"] == :issue
  end

  test "load_layers! lets issue policy.json beat workspace.json git compatibility" do
    dir = tmp_dir()
    File.mkdir_p!(Path.join(dir, "repo"))

    File.write!(
      Path.join(dir, "workspace.json"),
      Jason.encode!(%{
        "path" => "repo",
        "git" => %{"mode" => "branch", "base" => "main"}
      })
    )

    File.write!(
      Path.join(dir, "policy.json"),
      Jason.encode!(%{"git" => %{"mode" => "worktree"}, "rounds" => 3})
    )

    {policy, sources} =
      dir
      |> Policy.load_layers!(%{})
      |> Policy.resolve()

    assert policy["git"]["mode"] == "worktree"
    assert policy["git"]["base"] == "main"
    assert policy["rounds"] == 3
    assert sources["git.mode"] == :issue
    assert sources["rounds"] == :issue
  end

  test "load_layers! reads repo policy below issue and cli policy" do
    dir = tmp_dir()
    repo = Path.join(dir, "repo")
    File.mkdir_p!(Path.join([repo, ".tracefield"]))

    File.write!(Path.join(dir, "workspace.json"), Jason.encode!(%{"path" => "repo"}))

    File.write!(
      Path.join([repo, ".tracefield", "policy.json"]),
      Jason.encode!(%{"coverage" => %{"mode" => "relative"}, "embed" => "ollama"})
    )

    {policy, sources} =
      dir
      |> Policy.load_layers!(%{"coverage" => %{"mode" => "absolute"}})
      |> Policy.resolve()

    assert policy["coverage"]["mode"] == "absolute"
    assert policy["embed"] == "ollama"
    assert sources["coverage.mode"] == :cli
    assert sources["embed"] == :repo
  end

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "tracefield-policy-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
