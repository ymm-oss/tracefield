defmodule Tracefield.Policy do
  @moduledoc "Policy cascade loading and resolution."

  @known_top_keys MapSet.new([
                    "coverage",
                    "embed",
                    "recruit",
                    "rounds",
                    "git",
                    "sharing",
                    "warnings"
                  ])
  @sharing_modes ~w(shared independent combine)

  @default_policy %{
    "coverage" => %{"mode" => "absolute", "threshold" => 0.2},
    "embed" => "mock",
    "recruit" => false,
    "rounds" => 2,
    "sharing" => %{},
    "warnings" => %{
      "unowned" => %{"enabled" => true, "threshold" => 1.0},
      "stale" => %{"enabled" => true, "rounds" => 2}
    },
    "git" => %{
      "mode" => "current",
      "branch_template" => "tracefield/{slug}",
      "base" => "main",
      "remote" => "origin",
      "gh_cmd" => "gh"
    }
  }

  @spec default_policy() :: map()
  def default_policy, do: @default_policy

  @spec resolve([{atom(), map()}]) :: {map(), map()}
  def resolve(layers) do
    Enum.reduce(layers, {%{}, %{}}, fn {source, layer}, {effective, provenance} ->
      validate_top_keys!(layer)

      {
        deep_merge(effective, layer),
        Map.merge(provenance, provenance_for(layer, source))
      }
    end)
  end

  @spec load_layers!(String.t(), map()) :: [{atom(), map()}]
  def load_layers!(issue_dir, cli_policy_map) do
    [
      {:default, default_policy()}
    ]
    |> maybe_add_org_layer()
    |> maybe_add_repo_layer(issue_dir)
    |> maybe_add_issue_layer(issue_dir)
    |> maybe_add_cli_layer(cli_policy_map)
  end

  @spec summary(map(), map()) :: String.t()
  def summary(policy, provenance) do
    policy
    |> flatten()
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join(" ", fn {key, value} ->
      source = Map.fetch!(provenance, key)
      "#{key}=#{format_value(value)}(#{source})"
    end)
    |> then(&"policy: #{&1}")
  end

  @spec sharing_mode(map(), String.t()) :: String.t()
  def sharing_mode(policy, stage) when is_map(policy) and is_binary(stage) do
    policy
    |> Map.get("sharing", %{})
    |> Map.get(stage, "shared")
    |> validate_sharing_mode!(stage)
  end

  @spec validate_top_keys!(map()) :: :ok
  def validate_top_keys!(policy) when is_map(policy) do
    unknown =
      policy
      |> Map.keys()
      |> Enum.map(&to_string/1)
      |> Enum.reject(&MapSet.member?(@known_top_keys, &1))

    if unknown != [] do
      Mix.raise("unknown policy keys: #{Enum.join(Enum.sort(unknown), ", ")}")
    end

    validate_sharing_values!(policy)
    :ok
  end

  def validate_top_keys!(policy),
    do: Mix.raise("policy must be a JSON object: #{inspect(policy)}")

  defp maybe_add_org_layer(layers) do
    case System.get_env("TRACEFIELD_ORG_POLICY") do
      nil -> layers
      "" -> layers
      path -> add_non_empty_layer(layers, :org, read_policy_file!(path))
    end
  end

  defp maybe_add_repo_layer(layers, issue_dir) do
    with {:ok, workspace_path} <- workspace_path(issue_dir) do
      path = Path.join([workspace_path, ".tracefield", "policy.json"])

      if File.exists?(path) do
        add_non_empty_layer(layers, :repo, read_policy_file!(path))
      else
        layers
      end
    else
      :error -> layers
    end
  end

  defp maybe_add_issue_layer(layers, issue_dir) do
    workspace_git = workspace_git_policy(issue_dir)
    path = Path.join(issue_dir, "policy.json")

    file_policy =
      if File.exists?(path) do
        read_policy_file!(path)
      else
        %{}
      end

    issue_policy =
      workspace_git
      |> deep_merge(file_policy)

    add_non_empty_layer(layers, :issue, issue_policy)
  end

  defp maybe_add_cli_layer(layers, cli_policy_map) do
    add_non_empty_layer(layers, :cli, cli_policy_map || %{})
  end

  defp add_non_empty_layer(layers, _source, policy) when policy == %{}, do: layers
  defp add_non_empty_layer(layers, source, policy), do: layers ++ [{source, policy}]

  defp read_policy_file!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> tap(&validate_top_keys!/1)
  end

  defp workspace_path(issue_dir) do
    path = Path.join(issue_dir, "workspace.json")

    if File.exists?(path) do
      config = Jason.decode!(File.read!(path))

      case Map.fetch(config, "path") do
        {:ok, repo_path} -> {:ok, resolve_path(issue_dir, repo_path)}
        :error -> :error
      end
    else
      :error
    end
  end

  defp workspace_git_policy(issue_dir) do
    path = Path.join(issue_dir, "workspace.json")

    if File.exists?(path) do
      path
      |> File.read!()
      |> Jason.decode!()
      |> Map.get("git", %{})
      |> case do
        git when git == %{} -> %{}
        git -> %{"git" => git}
      end
    else
      %{}
    end
  end

  defp resolve_path(issue_dir, path) do
    if Path.type(path) == :relative do
      Path.expand(path, issue_dir)
    else
      Path.expand(path)
    end
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      if is_map(left_value) and is_map(right_value) do
        deep_merge(left_value, right_value)
      else
        right_value
      end
    end)
  end

  defp provenance_for(layer, source) do
    layer
    |> flatten()
    |> Map.new(fn {key, _value} -> {key, source} end)
  end

  defp flatten(map), do: flatten(map, [])

  defp flatten(map, prefix) when is_map(map) do
    Enum.flat_map(map, fn {key, value} ->
      flatten(value, prefix ++ [to_string(key)])
    end)
  end

  defp flatten(value, prefix), do: [{Enum.join(prefix, "."), value}]

  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value) when is_binary(value), do: value
  defp format_value(value), do: to_string(value)

  defp validate_sharing_values!(policy) do
    case Map.get(policy, "sharing") do
      nil ->
        :ok

      sharing when is_map(sharing) ->
        Enum.each(sharing, fn {stage, mode} ->
          validate_sharing_mode!(mode, stage)
        end)

      other ->
        Mix.raise("sharing must be a JSON object: #{inspect(other)}")
    end
  end

  defp validate_sharing_mode!(mode, _stage) when mode in @sharing_modes, do: mode

  defp validate_sharing_mode!(mode, stage) do
    label = if stage, do: "sharing.#{stage}", else: "sharing"
    Mix.raise("invalid #{label} #{inspect(mode)}")
  end
end
