# 依頼: コードを読み取り、FSL（形式仕様）として忠実に書き出す

## このシナリオの性質（抽出タスク）
これは「答えが一意でない発想」ではなく、**答えがほぼ一意（＝コードの実挙動）の抽出（convergent extraction）タスク**である。
価値は発散ではなく**接地（grounding）の精度**にある。中心課題は2つ:

1. **正しい読み取り** — コードの挙動を取り違えない（comprehension fidelity）。
2. **ハルシネーション** — コードに無い挙動・条件・不変条件を書かない（fabrication）。

両者はいずれも「仕様はXと言うが、コードはXを支持しない」という同型の誤りであり、**引用接地**で殺す。

## 2つの直交した機械的接地（設計の骨子）
| 誤り | 「仕様 ⇄ コード」 | 機械的接地 |
|---|---|---|
| 読み取り誤り＋ハルシネーション | 仕様がこのコードに**忠実か** | `relies_on` 引用（`file:line`）＋ verify 段（引用行を再オープンして非接地を棄却） |
| 内部不整合・非整形 | 仕様が**形式的に整合か** | **`fslc` 自身**（BMC/JSON、LLM 不使用。フロー後の手動裁定） |

## 一次資料の再参照（最重要の運用則）
PDF 読解の実測知見の写像: **レンズは自分の粒度で一次資料を再参照すると読み取り精度が格段に上がる。要約越しに書くな。**
- 各 actor は upstream の digest で済ませず、**当該コード領域を実際に再オープン**してから書く（codex-app-server は read-only で実ファイルを開け、開いた事実を provenance に自動記録する）。
- 粒度は小さく保つ（1 actor ＝ 1 領域）。大きいファイルは領域に分割して入力する。
- 再参照は **read 時（spec-draft）と reject 時（verify）の両方**で走らせる。read 時の再接地だけでも精度は格段に上がる。

## 対象コード（差し替え可能）
既定の例は **tracefield 自身のステータス状態機械**（`Active` / `Retracted` / `Superseded` と `retract` / `supersede` / 引用閉包）。
小さく実在する真の状態機械で、FSL の design 方言がちょうど対象とする題材。

領域は `inputs/region-*.md` のポインタで与える。**1 ポインタ = 1 領域 = 1 EVIDENCE actor**（`per_input`）。
ポインタは「コードそのもの」ではなく**実コードへの参照**であり、actor は指された実ファイルを再オープンして書く。書式:
```
# 領域: <名前>
- path: <パス: リポジトリ内ならスコープdir（codex の cwd）からの相対 例 ../../crates/...／外部コードはローカル絶対パス>
- lines: <開始>-<終了>（目安。前後も再オープンしてよい）
- 抽出対象: <仕様化すべき状態・遷移・ガード・不変条件・契約>
- 文脈: <呼び出し元/関連領域への最小の手がかり>
```
粒度の目安は **1 領域 = 1 関数〜数百行**。大きいファイルは複数領域に割る。
**別のコードを対象にするときは `inputs/region-*.md` を差し替えるだけ**でよい（フロー・エージェントは対象非依存）。
コミットされる既定例はリポジトリ内のコードを相対パスで指す（絶対パスを公開リポジトリに入れない）。外部コードを指すローカル絶対パスはコミットしない。

## ローカル設定（実行前に1回）
FSL スキルの複製を公開リポジトリに入れずドリフトも避けるため、`skills/` は **gitignore 済**。ローカルで FSL リポジトリへ**シンボリックリンク**を張る:
```sh
ln -s <fsl>/skills/fsl        scenarios/fsl-codespec/skills/fsl
ln -s <fsl>/skills/fsl-design scenarios/fsl-codespec/skills/fsl-design
```
（`<fsl>` = ローカルの FSL リポジトリ。）agents.json の `"skills": ["fsl","fsl-design"]` は**この配置のフェイルファスト**（未配置ならシナリオ読み込みが「skill fsl not found」で止まる）と provenance 帰属のためで、codex には本文を自動注入しない（注入は Ollama/OpenRouter 時のみ）。**codex は上記ファイルを cwd 相対で自分で開く**ので、配置さえあれば文法は届く。

## 出力・fslc ゲート・realize（決定的 ＋ 監査つき再実行 repair）
調査段は read-only。fslc 検証は**段7 `fslc_gate`（決定論コマンドステージ）が flow 内で実行**し、最終 `.fsl` の配置だけ realize で決定的に行う（エージェントにファイルを書かせない＝中核の provenance/監査を壊さない）。
- ASSEMBLE は整合した FSL design 仕様を **```fsl コードフェンス**で出す。各要素の依拠は FSL 行コメント `// relies_on: file:line`。落とした主張（反証・非接地で除外）と repair 注記は**フェンス外**（no-silent-drop）。
- **段7 fslc_gate（in-flow・第二の機械裁定・LLM 不使用）**: assemble の ```fsl を抽出し `fslc check`→`fslc verify`。結果は assemble を引用する observation（**retract 閉包内・exit を `meta.exit_code`**）。非ゼロ=赤は所見として残り run は止まらない。
- realize（最終配置のみ・決定的）:
  ```sh
  tracefield run --scenario-dir scenarios/fsl-codespec --persist scenarios/fsl-codespec/run.jsonl
  ./scenarios/fsl-codespec/realize.sh scenarios/fsl-codespec/run.jsonl <fsl>/specs/<out>.fsl
  ```
- **repair は監査つき再実行**: fslc_gate が赤なら、その出力（`fslc_gate` エントリ/`exit_code`）と該当 `// relies_on` を出典に spec を直して**フロー再実行**（各実行は別 provenance＝沈黙の上書きをしない。不変条件③）。
  - 書き換えの根拠は **`file:line` か fslc 診断のみ**。fslc を緑にするため制約を発明するな（緑-by-捏造は最大のハルシネーション源）。
  - fslc の反例は (a) コードの真の矛盾＝**発見として報告** / (b) 仕様の誤読＝該当コードを再オープンして修正。緑は必要条件であって十分条件ではない。
- `fslc` の保証の強さ（proved / bounded / unknown）を**言い換えで格上げするな**。実ステータスをそのまま記す。

## エージェントへの規律
- 賛辞・一般論・言い換えは書くな。**具体・因果・`file:line` 依拠**を要求する。
- コードが曖昧で挙動が確定できない箇所は、断定せず **[暫定]** と明示し、確認手段（読むべき行・走らせるべきテスト）を添えよ。
- FSL の構文は記憶で書くな（FSL は訓練データの少ないニッチ言語＝構文捏造の巣）。**構文・起草・repair の権威は FSL スキルを cwd 相対で開いて参照**せよ（出力言語にも一次資料再参照を適用。下記「ローカル設定」で配置）:
  - `skills/fsl/SKILL.md` ＋ `skills/fsl/reference.md`（構文の権威）
  - `skills/fsl-design/SKILL.md`（design 方言の起草手順と repair プロトコル）
  - codex は read-only でこれらを開き provenance に記録する。スキルに無い構文が要るなら**発明せず** `[暫定: この性質を表す FSL 構文を要確認]` と書いて止める。
- 日本語で書け（仕様本体の識別子・FSL 構文は除く）。
