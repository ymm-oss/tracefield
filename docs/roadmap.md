# ロードマップ — 最終目的から逆算した計画（2026-06-10 改訂）

> **最終目的（確定）**: ① **アプリ開発の AI 駆動開発**、② **コンサル業務のサポート**。
> **最優先目標（2026-06-11 確定）**: ①を「**Issue 詳細化 → 設計 → 実装 → QA を HITL 付きで完遂する開発パイプライン**」として実現する
> （設計: [`design-pipeline.md`](./design-pipeline.md)、判定ゲート **G3** = 実 Issue 1件をパイプラインだけで QA pass まで完遂）。
> 研究プログラムは完了（[`conclusions.md`](./conclusions.md)）、実題材での実走も確認済み（住宅サービスのアイデア出し）。
> 本書はこの2つの行き先から逆算して各フェーズを定義する。

## 0. 北極星 — 2つの行き先と tracefield の役割

### 行き先② コンサル業務サポート（近い・先に獲る）
- **形**: 複数レンズ（業界・財務・技術・顧客…）のエージェントが、クライアント文書・社内知見（私的文書）を
  土台に**引用付き**で発想・分析・リスクレビューする。住宅デモがまさにこの形だった。
- **発展形**: [`design-field-runner.md`](./design-field-runner.md) の Field Runner。`tracefield run` と
  `flow.toml` で stage / actor scaling / organ routing / feedback / gate を汎用化し、長時間調査や開発/QAフローを
  Reference/citation/retract の統治下で行う。
- **tracefield が与える独自価値**:
  - **来歴つき提案**: 「この提言は事実Xに基づく」が引用で示せる（成果物の説明責任）。
  - **訂正の波及管理**: クライアント情報の訂正（= B型汚染の撤回）→ 提案のどこが影響を受けるか即座に特定。
  - **健全性の可視化**: 分析が groupthink に陥っていないか（diversity/collapse）を毎回測定。
- **既存資産との距離**: 近い。ideate＋モード整備＋実データ差し替えでパイロット可能。**ローカル 12B で成立**（機微情報を外に出さない利点）。

### 行き先① アプリ開発の AI 駆動開発（遠い・段階的に）
- **形**: spec / ADR / 要件を Reference に接地した半溶解エージェントチーム（アーキテクト・セキュリティ・UX・QA…）が、
  設計判断・実装方針を**引用付き**で生成。**要件変更 = チャンクの retract → 影響を受けた設計判断・タスクの閉包隔離 → 再導出**。
  手続き（コーディング規約・レビュー観点）は**データ**として配布・版管理・撤回可能（k_p 軸）。
- **重要な構図**: 実装の器官はローカル 12B ではなく**強いコーディングモデル（Claude Code / codex CLI）**。
  Agent=状態+手続き、LLM=器官という設計（[`design-agent.md`](./design-agent.md)）がそのまま効く ──
  **tracefield は協調と来歴の層、コーディングエージェントは器官**。
- **既視感は正しい**: この2日間の tracefield 開発自体（Claude=オーケストレーター、codex=実装器官、
  brief=手続き、docs=Reference、commit=来歴）が**行き先①の手動プロトタイプ**だった。これを機構に置き換えていく。

---

## フェーズ1 — コンサル・パイロット（行き先②の最短実証）

| # | 項目 | 内容 | 完了条件 |
| --- | --- | --- | --- |
| 1-0 ✅ | 保全 | リモート repo 作成・push | 完了 |
| 1-1 ✅ | モードプリセット | 発散/収束/レビュー（brief-14） | `--mode` 実装・テスト済 |
| 1-2 ✅ | verify 実装 | `Reference.verify`（実在/active/接地判定、✓✗注記、verification_rate） | 実走 0.84 |
| 1-3 ✅ | 訂正デモ | `--correct auto`: most_cited 撤回→閉包隔離→note付き修復ラウンド | **実走済**（e20撤回→5案隔離→代替8案） |
| 1-4 ✅ | レポート出力 | Markdown（タスク/アイデア✓✗/訂正/健全性/横断合成） | `runs/housing-converge-report.md` |
| 1-5 🔶 | **実データ・パイロット** | 雛形・手順書 `scenarios/_template/` 整備済み。**題材選定＝ユーザー入力待ち** | 人間評価（G1） |

**ゲート G1**: 実題材で「実務で使える」と判定できるか。

## フェーズ2 — 開発パイロット（行き先①の最小実証）

| # | 項目 | 内容 |
| --- | --- | --- |
| 2-1 ✅ | dev シナリオ | `scenarios/tracefield-dev`: 実在アプリ=tracefield自身の要件/ADR/制約6チャンクを Reference 化、ARCH/SEC/QA/DX が引用付き設計判断を実走 |
| 2-2 ✅ | **要件変更デモ** | **実走済**: R3(ローカル限定)を撤回 → 引用グラフから**依存13判断を即時隔離** → 新前提で代替判断を再導出。撤回済みentryへの引用は verify が ✗ で検出 |
| 2-3 ✅ | 強い器官の接続 | `Tracefield.LLM.CLI`（claude -p 既定・--cli-cmd 可変）。haiku スモーク: 品質が劇的に向上（GDPR削除権×append-onlyの張力発見、verification 0.94） |
| 2-4 ✅ | 手続き=データの実用化 | 視点別方法論(設計整合/データ境界/検証可能性/互換)を procedure Entry で配布・実走。`--correct procedure:<ID>` で欠陥手続き撤回→当該判断の閉包隔離（テスト済・chunk撤回と同一機構） |
| 2-5 ✅(最小) | 自己適用（dogfooding） | tracefield が**自身の次機能（永続store）の設計判断を自身の設計文書に接地して導出**（CLI器官の判断は実装に使える品質）。brief→codex ループの tracefield 化は次段 |

**ゲート G2 ✅（機構レベル）**: 実プロジェクト（tracefield 自身）の文書で成立。28判断から影響13件を引用グラフで即時特定（手作業なら全件読解が必要）。形式的な precision 採点と外部プロジェクトでの再現は今後。

## フェーズ3 — 統治ループとインフラの完成（両行き先の共通基盤）

- **永続 store ✅（dogfooding 完結）**: tracefield 自身が導出した設計判断（JSONL append-only＋リプレイ/opts追加のみ/0600/破損耐性/冪等seed）を brief-17 として実装。`--store true` で run を跨いで知識・撤回状態が蓄積（R1/R2/R3 充足、65 tests）
- PCE gate（retracted/未verify 依存の案を durable 化前にブロック）/ 計器補修（permissive 判定・judge ドリフト対策の規約化）
- Jido AgentServer/supervision の本格活用 / クロスモデル IRR・品質比較

## フェーズ4 — 研究の残課題と対外発信（並走・任意）

- §14 の統計規模化（対外主張するなら必須）/ k_p>1（欠陥手続きの撤回→巻き戻し）/ EGI 上り / Exploration Retention 正式測定
- **対外発信**: 新規性あり（構造×契約の自覚・均質化ダイヤル・ファネル分解・手続き provenance）。記事/論文/登壇。

## フェーズ5 — プロダクト化（G1・G2 通過後に判断）

常設 store・Web UI・複数ユーザー・実案件運用。

---

## 次の壁（2026-06-18 外部評価より）

> 評価の核: tracefield の価値は「AIが賢く協働する」ことではなく、**AI出力を構造化履歴に固定し、責任・根拠・影響を後から辿れること**。
> よって主指標は死角発見数ではなく **Impact Recall / Precision**（悪い入力の影響範囲をどれだけ正確に特定できるか）。
> 骨格（ReferenceStore + citation + retraction + gate + artifact manifest）は有望だが、以下が未成立。優先度は主指標への効きで決める。

| 優先 | 壁 | 現状 | あるべき | 主指標への効き |
| --- | --- | --- | --- | --- |
| **P1** | citation の型付け + fallback 見直し | `citations: Vec<String>`。`apply_core_gates` は citation 空時に selected 先頭5件を fallback 補修 → 因果でなく「渡された入力」を巻き込み precision を下げる | `citation_type`（evidence / context / procedure / resolves_question / artifact_source / weak_dependency / fallback）で依存の意味を保持。retraction closure を型で重み付け | **直結**。Impact Precision の上限を決める |
| **P2** | retract 後の repair | downstream closure を Retracted にする**隔離**まで。再導出は feedback/再runで間接的にのみ | 汚染除去後に残存 entry だけで再推論 → candidate delta 再構成 → artifact 差分修復 → **Repair Quality** を測定 | **直結**。Reversibility の本丸・研究主アウトカム |
| **P3** | append-only event log / view 分離 | ReferenceStore は entries の Vec + next_id の mutable snapshot。retract は status 上書き、write_jsonl は全体書き出し | event log（created/retracted/citation_added/artifact_exported/gate_blocked/feedback_routed）と materialized view（active/retracted/closure/artifact 状態）を分離 | 統治基盤の前提。実務化で必須 |
| **P4** | 日本語 source grounding | `source_quote_candidate_is_prose` が ASCII alphabetic / lowercase ratio で prose 判定 → 日本語文書で破綻 | 言語非依存の quote 検査（evidence_quote の連続部分文字列照合は言語に依らせる） | コンサル②（日本語文書）の実用前提 |
| **P5** | prompt injection の taint model | HTML の script/style 除去のみ。本文レベルの間接注入は残る | source content（根拠として読む）/ source instruction（実行指示として読まない）/ tool instruction（system/scenario 由来のみ有効）の taint 区別 | web ingest 拡大時のセキュリティ |
| **P6** | 実験の実施 | 8条件の評価設計と成功/失敗基準は良いが、シナリオ数・反復・モデル・評価者数・seed・counterfactual re-run 回数が未定（§14 規模化＝フェーズ4と接続） | counterfactual re-run を ground truth の一次定義に、専門家裁定を補助に。事後LLM再構成 baseline 比で Impact Recall/Precision を実証 | 「有望な仮説」→「実証済み」への昇格に必須 |

**設計の指針**: P1（citation 型）は HigherGraphen 的には単純 edge でなく claim/evidence/transformation/artifact-section/decision/revision の高次関係。最小でも citation_type の導入から。
provenance log を ground truth と誤認しない（評価が明記）— event log は「改竄されていない」を保証するが「最初の記録が真」は保証しない、append-only は必要条件であって十分条件ではない。

---

## 推奨順序

1. **1-0 push（保全）** → **1-1 モード** → **1-2 verify** → **1-3 訂正デモ** ── ②の独自価値を一気通貫で。
2. **1-5 実データ・パイロット**（← 題材はユーザー選定。守秘があれば匿名化で可）→ G1。
3. G1 通過後、**2-1〜2-2（要件変更デモ）** ── ①のキラーデモは現行ハーネスで安価に作れる。
4. 2-3（強い器官）以降はコスト方針（クラウド利用の可否）を決めてから。

## リスク

- ローカル 12B の品質上限（②の分析は成立確認済み。①の実装生成はクラウド器官が前提）。
- 機微情報: ローカル完結が②の強み。クラウド器官導入時はデータ境界の方針が必要（私的文書はローカル器官のみ、等の混成も可能）。
- 一人運用: 各項目は半日〜2日粒度で刻む。
