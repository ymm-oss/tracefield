# MVP 設計 — 接地真実の妥当性を先に測る最小プローブ

> **位置づけ**: [`design-review.md`](./design-review.md) DR-19 の段階化に基づく第1段階。
> 本実験（[`experiment-plan.md`](./experiment-plan.md)）を凍結・実装する**前**に、最小コストで回す de-risking プローブ。
> 用語は [`glossary.md`](./glossary.md) 参照。

---

## 1. MVP が答える問い（hypothesis-confirming ではなく de-risking）

本実験の主アウトカム（Impact Recall/Precision）は、**反実仮想再実行で作る接地真実が成立している**ことを暗黙の前提にしている。MVP はこの前提自体を先に検証する。

> **主問い**: 反実仮想差分は、汚染入力の**因果影響**を、LLM 探索の**実行ごとの分散**から分離できるか？（DR-1）
> **副問い**: その分離可能性は、free-form（C4）と半溶解性（C5）で**対称か**？（DR-2）

- これらが **Yes** なら、本実験の接地真実は成立する見込み → pre-registration を埋めて本実験へ。
- **No / 曖昧**なら、接地真実の作り方を再設計する（branch-point intervention、低温度化、探索の制約、または別の接地法）必要があり、**それを先にやる**。フルシステムを作り込むのは無駄。

> ⚠️ MVP の見出し成果は「C5 が C4 に勝ったか」ではなく、**接地真実の信号対雑音比（SNR / 分離可能性）** である。ここを取り違えない。

---

## 2. スコープ（意図的に最小化）

| 軸 | MVP | 本実験 |
| --- | --- | --- |
| シナリオ | **1**（§5 の企業向けAIアシスタント） | 複数（DR-14） |
| 汚染入力 | **1 = 汚染A**（同意の過大主張） | A/B/C + デコイ（DR-4） |
| 条件 | **C4 と C5 のみ** | C1–C8 |
| 評価 | **自動プロキシ指標のみ**（専門家パネルなし） | 専門家裁定 + ブラインド |
| 半溶解性 | **薄い実装**（provenance + candidate delta + 簡易 PCE gate） | フル（sensitivity profile / frame revision / risk-adjusted granularity 含む） |

**汚染A を選ぶ理由**: A は「派生要約・推薦へ伝播すべき事実の過大主張」で、純粋な**影響追跡**課題。B/C は撤回後の**信念改訂**課題（DR-11）で複雑なため MVP では除外する。

**専門家を使わない理由**: MVP の核心（SNR 測定）は**機械的な差分**で測れる。専門家判断（妥当性・介在性）は本実験の対象で、ここでは不要。安く速く回すことを優先。

---

## 3. 核心プロトコル — 分散characterization

接地真実の SNR を測るため、汚染状態を固定したまま seed を変えた反復を取る（DR-1 の提案）。

```
状態 A（汚染あり）: 同一タスク・同一汚染A を含め、seed を変えて N 回実行  → {A_1 … A_N}
状態 B（汚染なし）: 汚染A を除去/訂正版に置換し、seed を変えて N 回実行 → {B_1 … B_N}
```

正規化済み出力に対する差分関数 `d(out_i, out_j)`（§4.1）を使い、次の2分布を作る。

| 分布 | ペア | 意味 |
| --- | --- | --- |
| **within（雑音床）** | `d(A_i, A_j)`、`d(B_i, B_j)`（同一状態内） | 汚染と無関係な実行ごと分散 |
| **between（信号+雑音）** | `d(A_i, B_j)`（状態をまたぐ） | 汚染の因果影響 + 実行ごと分散 |

**分離可能性 = between が within より確率的に大きいか**。効果量で定量化する（例: Cliff's δ / AUC / 標準化平均差）。

- AUC ≈ 0.5 → 汚染影響は雑音と区別できない → **接地真実は無効**（Phase 1 ゲート不合格）。
- AUC が高い → 信号が分離できる → 反実仮想法は MVP シナリオで有効。

これを **C4 と C5 の両方**で行い、`SNR(C5) ≫ SNR(C4)` なら DR-2 の非対称（測定法バイアス）が現実に存在することの証拠になる。

---

## 4. 自動プロキシ指標

### 4.1 条件中立な項目空間と差分関数（DR-2, DR-10）

出力をそのまま比較しない。各 run の出力を**原子 claim / recommendation の集合**へ正規化してから比較する。

```
1. 抽出: 固定プロンプトの LLM で、各 run の出力を atomic claim / recommendation のリストへ分解
2. 整合: run をまたいで意味的に等価な claim をクラスタ化（埋め込み類似度の閾値 or LLM マッチング）
3. 差分 d: claim クラスタの集合差（出現/非出現）。必要なら重み付き Jaccard 距離など
```

- これにより candidate delta 等の**条件固有型に依存しない**比較が可能（DR-2）。
- 「1つの影響が claim/trace/recommendation に多重出現」する重複は、クラスタ化で吸収（DR-10）。

### 4.2 反実仮想由来の接地集合

within の雑音床を超えて **A 群で B 群より有意に高頻度**で出現する claim クラスタを、「汚染A に起因する影響項目」と定義する。これが MVP の接地真実（自動版）。

### 4.3 プロキシ Impact Recall / Precision

各システムが「汚染A の影響あり」と**自己申告**した集合を、§4.2 の接地集合と照合する。

- **C5**: append-only provenance から「汚染A を親に持つ」claim 集合を抽出。
- **C4**: 探索後に強モデルへ全 transcript を渡し、汚染A の下流影響を再構成させた集合。

```
proxy Impact Recall    = |接地集合 ∩ システム申告| / |接地集合|
proxy Impact Precision = |接地集合 ∩ システム申告| / |システム申告|
```

> これは**プロキシ**。専門家裁定（二次接地）は MVP では行わない。本実験で追加する。

---

## 5. フェーズと go/no-go ゲート

```
Phase 0 ─→ Phase 1 ══(GATE 1)══→ Phase 2 ══(GATE 2)══→ Phase 3 ──→ 判断
 配線      雑音床測定            非対称チェック         プロキシR/P
```

### Phase 0: 配線（システム不要）
- シナリオ・汚染A・訂正版（状態B）を**具体的 fixture** に確定（DR-14 の縮小版）。
- §4.1 の抽出→整合→差分パイプラインを実装し、トイ入力で妥当性を確認（同一出力で d≈0、無関係出力で d 大）。

### Phase 1: 雑音床測定 ← **最重要・最安**
- C4 相当の free-form 探索のみを実装（数エージェントの対話ループ）。
- 状態 A / B × N 回実行 → §3 の within / between 分布 → **SNR / AUC** を算出。
- **温度の影響も見る**（default vs 低温度）。低温度で SNR が改善するなら DR-1 の安価な緩和策になる。

> **GATE 1**: within を超える分離が得られるか？
> - 合格 → Phase 2 へ。
> - 不合格 → **ここで停止**。接地真実の再設計（branch-point intervention 等）を本実験より先に行う。フルシステムは作らない。

### Phase 2: 半溶解性（薄い実装）と非対称チェック
- 薄い C5 を実装: **append-only provenance + candidate delta 抽出 + 簡易 PCE gate（LLM チェック）** のみ。
  - 含めない: sensitivity profile / frame revision trigger / risk-adjusted granularity（本実験向け・MVP のスコープ外）。
- C5 でも状態 A/B × N → `SNR(C5)` を算出。

> **GATE 2**: `SNR(C5)` と `SNR(C4)` を比較。
> - 同程度 → cross-condition 比較は公平に成立しうる。
> - `SNR(C5) ≫ SNR(C4)` → **DR-2 のバイアスが実在**。本実験では接地真実を条件中立化する策（§4.1 の正規化強化、または free-form を主比較から外す）を pre-reg で確定する必要あり。いずれにせよ Phase 3 へ進み記録。

### Phase 3: プロキシ R/P
- C4（事後再構成）と C5（provenance 申告）の自己申告集合を §4.2 接地集合と照合し、proxy Impact Recall/Precision を算出。
- これは本実験の**予備推定**であり、効果量と分散を得て **DR-5 の検出力分析**（本実験の n 決定）に使う。

---

## 6. MVP パラメータ（提案値・要確認）

| パラメータ | 提案値 | 備考 |
| --- | --- | --- |
| シナリオ | 企業向けAIアシスタント（§5） | 1つ |
| 汚染入力 | 汚染A のみ | 影響追跡課題 |
| 反復回数 N（状態あたり） | **8**（最低 5、できれば 10） | 分散推定に足る最小限。Phase 1 で増やす余地 |
| 条件 | C4 / 薄い C5 | — |
| 探索モデル | ローカル Ollama `gemma4`（12b/26b）に固定 | seed・temperature を明示制御し記録（DR-1） |
| 抽出/再構成モデル | 同上（claim 抽出・整合・C4 事後再構成に使用） | LLM ベースの claim マッチングで埋め込み依存を回避 |
| 温度条件 | default と 低温度の2点 | DR-1 の緩和策探索 |
| 分離可能性の判定 | Cliff's δ / AUC（しきい値は Phase 0 でパイロット） | — |
| 評価 | 自動プロキシのみ | 専門家なし |

> seed・モデルバージョン・温度・プロンプトは**全 run で記録**し、再現可能にする（残存非決定性の扱いは pre-reg §5 / DR-1）。

---

## 7. スコープ外（MVP では**やらない**）

- 専門家裁定・ブラインド採点・IRR（本実験：DR-3, DR-18）。
- 汚染 B/C（信念改訂課題：DR-11）・デコイ入力（DR-4）。
- 条件 C1/C2/C3/C6/C7/C8。
- フル半溶解性（sensitivity profile / frame revision trigger / risk-adjusted granularity / packaging loss 評価）。
- 複数シナリオ（DR-14）。
- Containment / Reversibility / Repair / Novel-Interstitial Concern などの本実験アウトカム。

これらは MVP のゲートを通過してから本実験で扱う。

---

## 8. MVP の成果と本実験への接続

MVP は次を出力する。

1. **接地真実の SNR / 分離可能性**（Phase 1）→ 反実仮想法が成立するかの判断材料（DR-1）。
2. **SNR の条件間対称性**（Phase 2）→ cross-condition 比較の公平性の証拠（DR-2）。
3. **proxy Impact Recall/Precision の効果量・分散**（Phase 3）→ 本実験の**検出力分析と n 決定**の入力（DR-5）。
4. 自動 claim 抽出/整合パイプライン → 本実験の item 正規化（DR-10）の基盤として再利用。

これらが揃って初めて [`pre-registration.md`](./pre-registration.md) の主要項目（DR-1, DR-2, DR-5, DR-10, DR-15）を**根拠を持って凍結**できる。

---

## 9. 実装の足場（Elixir / mise）

**スタック**: **Elixir**（mise で導入: erlang 29.0.1 / elixir 1.20.0-otp-29、`mise.toml` でピン）。
半溶解性の語彙（Field Actor / append-only provenance / 並行 run の監視）が OTP のアクターモデル・
イミュータビリティ・supervision と素直に対応する。

**LLM provider**: LLM 呼び出しは behaviour で抽象化し、アダプタを差し替える（provider 決定は実装をブロックしない）。

| アダプタ | 用途 | 備考 |
| --- | --- | --- |
| `Tracefield.LLM`（behaviour） | 最小インターフェース（`complete/2` 等） | seed・temperature を引数で受ける |
| `Tracefield.LLM.Mock` | **Phase 0** | 決定的な擬似応答。LLM 不要でパイプライン検証 |
| `Tracefield.LLM.Ollama` | **Phase 1+** | ローカル Ollama（`localhost:11434`, `gemma4`）直叩き。**seed/temperature を明示制御**でき DR-1 に最適 |

> 実装（コード生成）は **codex CLI に委譲**。実験ランタイムの LLM 呼び出しは codex を経由しない
> （agent ラッパで seed/温度を制御できないため）。

想定レイアウト:

```
tracefield/
├── docs/                              # 既存
├── scenarios/enterprise-assistant/    # Phase 0 fixture（作成済み）
├── lib/tracefield/
│   ├── llm/                  # behaviour + Mock / Ollama アダプタ
│   ├── explore/              # C4: free-form 探索ループ（Task/GenServer）
│   ├── semisoluble/          # C5（薄い）: provenance + candidate delta + 簡易 gate
│   ├── ground_truth/         # 反実仮想 runner（A/B × N）+ within/between 差分
│   ├── normalize/            # claim 抽出 → LLMマッチング整合 → 差分 d
│   └── metrics/              # SNR / AUC(Cliff's δ) / proxy Recall・Precision
├── test/                     # 単体テスト（Phase 0 のトイ検証含む）
├── runs/                     # run ログ（seed・model・temp・出力を JSON で記録）
├── mise.toml                 # erlang/elixir のピン
└── mix.exs
```
