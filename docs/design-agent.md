# 設計 — Agent 境界の再定義（Agent = 状態 + 手続き）

> ユーザー定義（2026-06-10）: **「エージェントは状態と手続きを行える主体」**。境界を LLM としてではなく
> AI エージェントとして成立させる。[`design-reference.md`](./design-reference.md) v2（共有状態基盤）と対をなす
> アーキテクチャの主体側の定義。関連: [`overview.md`](./overview.md) §0。

## 1. 原則 — 単位は LLM ではなくエージェント

```
Agent = { identity（偏りアンカー・profile）,
          private state（store に書かない私的領域）,
          shared-state access（Reference への absorb/serve 権）,
          procedures（型付き・版付きの手続き群） }

LLM   = 無状態の推論器官（organ）。エージェントの手続きが呼び出す部品であり、主体ではない。
```

**帰結（カテゴリーエラーの解消）**: これまでの「モデル境界は依然トークン」という限界（experiment-results §10、
design-reference §13）は、**LLM をエージェントと同一視した誤り**だった。トークンは器官の内部事情
（人間のニューロン発火が会話の境界でないのと同じ）。**エージェント間の境界は store** ── 構造化・永続・
検証可能な状態 ── であり、これは言語ストリームの帯域制約に縛られない。

**人間との対比の架構化**: 人間＝状態も手続きもエクスポート不能（閉じた主体）。
エージェント＝状態（信念・仮説）も手続き（やり方）も外部化・移転・検証可能（開いた主体）。
半溶解＝その開放性を、偏り（identity・private state・自前の手続き）を温存する深さで使う。

## 2. 溶解の2次元化 — 状態 × 手続き

| 軸 | 共有されるもの | 完全融合の病理 | 半溶解 |
| --- | --- | --- | --- |
| **状態（k_s）** | 信念・仮説・観察（Reference の Entry） | 全員同じ信念＝groupthink | 選択的 pull ＋ 私的領域 |
| **手続き（k_p）** | 検証手続き・判定基準・検索方策・スキル | 全員同じやり方＝盲点の同期 | **選択的採用＋出所記録** |

- LLM エージェントの手続きは実質 **プロンプト/方策/ツール設定＝データ** → Reference に Entry として格納可能
  （`type: procedure`, version, author, citations）。
- 手続きの**採用イベントも citable**: 「BIZ が SEC の verify-procedure v2 を採用」が provenance 辺になる。

## 3. 統治の手続きへの拡張（新規・on-thesis）

汚染は**事実**だけでなく**やり方**にも宿る（欠陥ヒューリスティック・誤った判定基準の伝播）。
Agent=状態+手続き と定義すると、実証済みの防御機構がそのまま手続きに適用できる:

- 手続き Entry の **retract** → 採用履歴（provenance 辺）の閉包 → **その手続きで生成された結論まで隔離・再評価**。
- これは Path E（撤回→切除→修復）の手続き版であり、同一機構の再利用。

## 4. Elixir/OTP への自然な写像

| 概念 | OTP 実装 |
| --- | --- |
| Agent（状態+手続きの主体） | **GenServer**（state + handle_* = まさに状態+手続き） |
| procedures | ハンドラ＋手続き Entry（データ）を解釈する実行器 |
| LLM 器官 | 手続き内から呼ぶ effect（既存 `Tracefield.LLM`） |
| Reference / store | 共有プロセス（GenServer/ETS、永続化付き） |
| Field（場） | supervision tree 下のエージェント群＋store |

Field Actor（experiment-plan の語彙）がここで文字通りの実体になる。

## 5. 実装スケッチ

```
Tracefield.Agent (GenServer)
  state: %{id, profile, anchor, private_notes, procedures: %{name => %{version, spec}}}
  loop（1ターン）:
    perceive  : Reference.serve(profile/クエリ, scope k_s)   # pull・選択的
    deliberate: LLM 呼び出し（手続き spec が定めるプロンプト/判定）
    absorb    : Reference.absorb(entries, citations)          # 引用付き書き込み
    adopt     : Reference の手続き Entry を選択的に採用（k_p, 出所記録）
    on_retract: 撤回イベント受信 → 自分の依拠 Entry/手続きの閉包処理
```

## 6. 実験への含意

- 用量反応が **2D 格子（k_s × k_p）** になる。まず **k_p=0 で状態軸**（design-reference v2 §14 の計画どおり、較正済み計器を再利用）→ 次に手続き軸。
- 手続き軸の新しい問い: 「手続きの共有は収束を速めるか・盲点を同期させるか」「欠陥手続きの撤回で、どこまで結論を巻き戻せるか」。
- 攻め（協働の質）と守り（状態・手続き両方の統治）が**同一のエージェント+store 基盤**で測れる。

## 7. 限界

- 手続き＝プロンプト/方策である限り、その**実行品質は器官（LLM）に依存**する（手続きを共有しても器官が弱ければ同じ実行はされない）。
- private state と shared state の線引きはエージェント自身の申告に依る（外部化の誠実さ問題 ── provenance の真正性問題 §13 と同型）。

## 8. Agent ライブラリ評価（2026-06 調査）

**結論: [Jido](https://github.com/agentjido/jido)（v2.0、2026-02 リリース）が本プロジェクトの Agent モデルにほぼ一対一で適合する。**

| 本設計の概念 | Jido での対応 | 適合 |
| --- | --- | --- |
| Agent = 状態+手続きの主体 | Agent = **schema 検証付き不変 state** + **Action**（コンパイル時 schema 付き純粋関数モジュール） | ◎ 概念一致 |
| 手続きの実行 | `cmd/2`: action in → 新 state + **Directive**（副作用を**データとして記述**、実行は OTP ランタイム） | ◎ 副作用がデータ＝**ログ可能・決定的**で実験規律と好相性 |
| LLM=器官（差し替え可能） | `jido_ai` は**任意パッケージ**。core だけ使い、Action 内から既存 `Tracefield.LLM`（Mock/seed 規律）を呼べる | ◎ |
| 偏りアンカー/private state | schema 付き state の一部 | ○ |
| Reference / provenance / 引用照合 / 撤回閉包 | **どのライブラリにも無い**（本プロジェクトの中核独自部） | — 自作のまま |
| 手続き=データ（採用・引用・撤回可能な Entry） | Jido Action は**コンパイル済みモジュール**で runtime データではない → procedure-entry 層は自作し、汎用 `InterpretProcedure` Action が解釈する形 | △ 実行殻として利用 |

他候補: **LangChain Elixir**（チェーン/プロバイダ層。agent-as-process でなく、LLM 層は自前規律を崩すため不採用）/
**Ash AI**（Ash 全面採用が前提で研究ハーネスには過重）/ Agens・AgentForge・Magus 等（小規模・保守薄）。

**リスク**: Jido 2.0 はリリース約4ヶ月で API 変動の可能性。codex にとって新規フレームワーク（実装リスク増）。
3エージェント×2ラウンドの実験ループには過剰装備の面もある（素の GenServer なら~100行）。

**採用方針（決定）**:
1. **brief-9 で Jido core を試験採用**（jido_ai は使わず、LLM は既存 behaviour 経由）。ただし **`Tracefield.Agent` を薄い facade** とし
   Jido への直接依存を1モジュールに封じる。タイムボックス内で seed/Mock 規律・テストと衝突したら**素の GenServer に fallback**
   （facade のおかげで差し替えは局所）。
2. 本実装（製品化）フェーズでは Jido の supervision・永続化・観測性・MCP センサーを本格活用。
