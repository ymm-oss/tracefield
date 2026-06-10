# シナリオ雛形 — 実データで ideate を回す手順

実題材（コンサル案件・企画検討・設計レビュー等）で `tracefield.ideate` を回すための雛形。
このディレクトリをコピーして書き換える:

```sh
cp -r scenarios/_template scenarios/<案件名>
```

## 構成

| ファイル | 内容 | 書き方 |
| --- | --- | --- |
| `task.md` | 題目（何を考えたいか） | 背景・対象・狙い・求めるアウトプットを箇条書きで。具体的なほど良い |
| `agents.json` | 視点（レンズ）の定義 | 3〜5体。`id`（大文字英数）/`domain`（英語ケバブ）/`desc`（その視点が何を最重視するか）/`private_doc` |
| `private/<名前>.md` | 各視点の**私的知識** | その視点だけが知る事実・データ・所見を箇条書きで5項目前後。**ここの質が出力の質を決める** |
| `procedure.md` | 生成手続き（任意） | 無ければ組み込み既定。アウトプットの型（「サービス名＋説明」等）をここで指定 |
| `procedure-review.md` | レビュー手続き（任意） | `--mode review` 用。無ければ組み込みのリスクレビュー手続き |

## 私的知識の書き方のコツ

- **視点ごとに重ならない**事実を入れる（重なると横断合成の価値が出ない）。
- 数値・固有の制約・現場の生の声が効く（一般論は LLM が既に知っている）。
- 機微情報: ローカル Ollama 構成なら外部送信なし。それでも匿名化推奨（社名・個人名を伏せる）。

## 実行

```sh
# 発散（切り口を広く）
mise exec -- mix tracefield.ideate --scenario scenarios/<案件名> --adapter ollama \
  --mode diverge --model gemma4:12b --report runs/<案件名>-diverge.md

# 収束（統合案へ練り上げ）+ 訂正デモ
mise exec -- mix tracefield.ideate --scenario scenarios/<案件名> --adapter ollama \
  --mode converge --correct auto --report runs/<案件名>-converge.md

# リスクレビュー
mise exec -- mix tracefield.ideate --scenario scenarios/<案件名> --adapter ollama \
  --mode review --report runs/<案件名>-review.md
```

レポートは Markdown（アイデア＋引用✓✗＋健全性＋横断合成）。`--correct auto` を付けると
「最も依拠された知見が誤りだったら」の撤回→隔離→代替案生成まで再現する。

## 健全性メトリクスの読み方

- **diversity 低 / collapse 高** → 視点が混ざりすぎ（diverge モードか k を下げる）。
- **cross-author が少ない** → 私的知識が重なっているか、視点定義が近すぎる。
- **verification_rate 低** → 引用が言いっ放し（根拠の薄い案が多い）。
