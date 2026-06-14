# 実装ブリーフ — theater 検出実験（contrastive serve は genuine か）

> 対象: codex（ハーネス実装＋mock検証）。実 ollama 走行と結果解釈は Claude。
> 前提: `feat: 差延的 serve (policy: :contrastive)`（commit 00760e4）が入っていること。
> 検証する命題（会話で確立）: **差延（contrastive）は異質性の「乗数」であって「源泉」ではない。**
>   - 接地（grounded）あり → genuine な横断発見が増える
>   - 接地なし（homogeneous）→ diversity だけ上がり発見は増えない（= theater）

## 0. 設計（2×2×seeds の交互作用）

既存 `mix tracefield.hetero`（§14 の serve×aware ハーネス、`lib/mix/tasks/tracefield.hetero.ex`）に
**heterogeneity 軸**を1本足す。固定条件は §14 で解錠済みの構成: `aware=1, k_s=2, k_p=1`。

| 軸 | 値 |
| --- | --- |
| serve | `diverse`, `contrastive`（floor 比較に `similar` も任意） |
| hetero | `grounded`（現状＝エージェント別の私的文書）, `homogeneous`（全エージェントに同一文書） |
| seed | 2000.. （既存どおり） |

- **grounded** = 現状の `load_private_docs/1`（SEC/BIZ/UX が別々の私的文書。植え込み矛盾 I1〜I3 は2文書にまたがる＝発見は**横断**を要する）。
- **homogeneous** = 全エージェントに**同一文書 = 3私的文書の連結**を渡す。**総情報量は grounded と同一**に保ち、分布の異質性だけを潰す対照（＝各エージェントが矛盾の両半を自前で持つので、発見は横断を要さない）。

### 解釈フレーム（Claude が結果に対して行う）
一次 = `disc_strict`（決定的）。theater 監視 = `diversity` / `collapse_rate`。
**serve 効果（contrastive − diverse）を hetero レベル内で比較**:
- **genuine**: grounded で contrastive の `disc_strict` > diverse。
- **theater**: homogeneous で `diversity`↑ / `collapse`↓ なのに `disc_strict` は diverse と同等（serve に非感応）。
- 望む結果 = 「disc 利得は grounded だけ／diversity 利得は両方」＝命題「乗数であって源泉でない」を支持。
- 反証 = grounded でも contrastive が disc を上げない（→ 機構として無価値、revert 検討）／homogeneous でも disc を上げる（→ 交絡、設計見直し）。

## 1. スコープ

**IN（codex）**
- `tracefield.hetero` に `--hetero grounded,homogeneous`（既定 `grounded`＝完全後方互換）
- スイープへ hetero 軸を追加し、homogeneous 用の同一文書を構築して run_one に渡す
- 行・サマリ・出力・serve_trend を hetero でキー分け
- Mock アダプタでの配線テスト（＋極小 mock スイープで両レベルが出ることを確認）

**OUT（Claude が後段で）**
- 実 ollama 走行（`--adapter ollama --model gemma4:12b`）と結果解釈
- λ 調整・contrastive の昇格/revert 判断（結果次第）

## 2. 対象コードと現状（`lib/mix/tasks/tracefield.hetero.ex`）

- option 定義: `parse_args/1`（strict キーワード 90-102）＋ 戻り keyword 108-122
- run_experiment スイープ: 53-71 `for k <- ks, kp <- kps, serve <- serves, aware <- awares, index <- 0..(seeds-1)`
- private_docs: 既定 `load_private_docs("scenarios/enterprise-assistant/private")` 48-51、`load_private_docs/1` 360-366（`%{"SEC"=>..,"BIZ"=>..,"UX"=>..}`）
- run_one: 125-225（`private_docs` を受け、各 agent に `private_doc: Map.fetch!(private_docs, agent.id)` 163 で割当）。結果 row 204-224。
- summary_by_cell: 262-280（セルキー `{k,kp,serve,aware}`）
- serve_trend: 323-334（キー `{k,kp,aware}`）／aware_trend 336-347
- print/persist: 387-452 / 368-385
- serve パーサ `parse_serves/1` 495-506（`contrastive` 追加済み）

## 3. 実装仕様

### 3.1 option
- `parse_args` strict に `hetero: :string` 追加。戻りに `heteros: parse_heteros(Keyword.get(opts, :hetero, "grounded"))`。
- `parse_heteros/1`: カンマ分割 →`"grounded"->:grounded` / `"homogeneous"->:homogeneous` / その他 `Mix.raise`。
- `run_experiment`: `heteros = Keyword.get(opts, :heteros, [:grounded])`。

### 3.2 文書セットの構築（run_experiment 内、private_docs 取得直後）
```
grounded_docs = private_docs                       # 既存
homogeneous_docs =
  (combined = grounded_docs |> Map.values() |> Enum.join("\n\n"))
  |> then(fn combined -> Map.new(Map.keys(grounded_docs), fn id -> {id, combined} end) end)
docs_for = fn :grounded -> grounded_docs; :homogeneous -> homogeneous_docs end
```

### 3.3 スイープに hetero を追加
```
for k <- ks, kp <- kps, serve <- serves, aware <- awares, hetero <- heteros, index <- 0..(seeds-1) do
  run_one(scenario, [private_docs: docs_for.(hetero), hetero: hetero, ...既存...])
end
```
- `run_one`: opts から `hetero` を取り、結果 row に `hetero: hetero` を追加（204-224）。

### 3.4 集計・出力
- `summary_by_cell`: group キーを `{k,kp,serve,aware,hetero}` に拡張、row にも `hetero` を含める。
- `serve_trend`: キーを `{k,kp,aware,hetero}` に拡張（**hetero レベル内で serve 比較が出る**こと＝本実験の主出力）。`run_experiment` 呼び出し・`print_result` の対応も更新。
- `print_result`: runs 表・aggregate 表・serve trend 行に `hetero` 列/キーを追加。disc_judge/icc/coverage/diversity/collapse は既存どおり。
- 既存 trend（kp/aware/diversity）は hetero=grounded のみ、もしくは hetero でキー分け ── 最小で可（壊さないこと優先）。

### 3.5 後方互換
- `--hetero` 省略時 `[:grounded]` で**現状と完全一致**の出力（既存テスト不変）。

## 4. テスト（Mock アダプタ、`test/`）

既存 hetero テスト（`grep -rln "Tracefield.Hetero\|run_experiment" test/`）に追加 or 新規:
1. `parse_heteros`: `"grounded,homogeneous"` → `[:grounded,:homogeneous]`、不正値は raise。
2. **homogeneous 文書割当**: homogeneous セルで全 agent の `private_doc` が同一（= 連結文字列）であること。grounded セルでは agent ごとに異なること。
   （`run_one` を小入力で呼ぶ or Agent 構築を覗ける形に。Agent.new の private_doc を検証できる経路で。）
3. **スイープ網羅**: `serves=[:diverse,:contrastive]`, `heteros=[:grounded,:homogeneous]`, seeds=1 → runs が 4 セル、summary キーに hetero が入る。
4. 後方互換: hetero 省略 → 既存挙動（セルキー数・出力）不変。

Mock は決定的だが発見の意味は無い ── テストは**配線**（セル生成・文書割当・キー）の検証に限定。科学的判定は実走で。

## 5. 完了基準（codex）

- `mix test` 緑（新規含む）。`mix format`（変更ファイル）済。
- `mix tracefield.hetero --adapter mock --serve diverse,contrastive --hetero grounded,homogeneous --aware 1 --ks 2 --kp 1 --seeds 1` が走り、**両 hetero レベル × 両 serve = 4 セル**を出力。
- `--hetero` 省略時の出力が現状と一致（後方互換）。
- report: `git diff --stat`、3.2-3.4 の実コード、mock スイープ出力（4セル）、`mix test` 結果。

## 6. 実走（Claude、codex 完了後）

```
mix tracefield.hetero --adapter ollama --model gemma4:12b \
  --serve diverse,contrastive --hetero grounded,homogeneous \
  --aware 1 --ks 2 --kp 1 --seeds 3
```
（12 runs。まず seeds=2 のパイロット → シグナルあれば seeds 増。）
→ §0 の解釈フレームで disc_strict（一次）と diversity/collapse（theater 監視）を読み、contrastive の keep/promote/λ調整/revert を判断。
