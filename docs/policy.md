# ポリシー

tracefield のポリシーは、次の5層を下から順に重ねる。

```
default < org < repo < issue < cli
```

右側ほど優先順位が高い。つまり CLI 指定は issue 設定より強く、issue 設定はリポジトリ既定より強い。

このリポジトリの既定ポリシーは `.tracefield/policy.json` で `git.mode = "branch"` とする。main への直接コミットを防ぎ、issue ごとの作業を分離し、差分をレビュー可能な単位として残すためである。

issue ごとに別の運用が必要な場合は、issue ディレクトリの `policy.json` で上書きする。たとえば PR モードにする場合は次のように書く。

```json
{"git":{"mode":"pr"}}
```
