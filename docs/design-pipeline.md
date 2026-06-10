# 設計 — AI 駆動開発パイプライン（Issue 詳細化 → 設計 → 実装 → QA、HITL 付き）

> **目標（ユーザー定義 2026-06-11）**: tracefield の目標は、まず **AI 駆動開発を Issue の詳細化・設計・実装・QA まで完遂**できること。
> **HITL（Human-in-the-Loop）も行える**必要がある。
> 本書はこの目標をパイプラインとして設計し、既存資産とのギャップを特定する。

## 0. tracefield が汎用エージェントパイプラインと違う点（価値の核）

1. **端から端までの provenance**: QA 判定 → 実装変更 → 設計判断 → 要件 → Issue が全て citation で繋がる。
   **途中で要件が変わったら、依存する設計判断・実装タスクが閉包隔離され、修復が走る**（§2-2 で実証済みの機構をパイプライン全長に）。
2. **HITL = 人間 Actor のターン（ANT 的対称性、2026-06-11 改訂）**: 人間は系の外の承認者ではなく、
   **器官が人間であるだけの Actor**（[`design-agent.md`](./design-agent.md) §10）。gate は特別な機構ではなく
   「その stage の名簿に人間 Actor がいて、手続きが『レビューし承認/修正せよ』である」こと。
   人間の回答・承認も citable entry ── **誤った前提での承認の撤回 → 閉包隔離**も同じ機構で扱える（統治の対称性）。
3. **多レンズの接地**: 詳細化も設計も QA も、偏りを持つエージェント群が文書チャンクに引用付きで行う（既実証）。
4. **健全性の常時計測**: 各 stage の diversity/verification/文脈予算が測られる。

## 1. パイプライン構造

1 Issue = 1 クラスタ（ディレクトリ＋store）。stage を進むたび成果物が entries ＋ Markdown で残る。

```
issue.md（入力）
  ↓ refine（詳細化）       → requirements（受入基準・影響範囲・制約）+ open questions
  ── HITL gate R ──        → 人間: 質問に回答（HUMAN entries）・要件を承認/編集
  ↓ design（設計）          → 設計判断 entries（要件・ADR チャンクを citation）+ design.md
  ── HITL gate D ──        → 人間: 判断を承認/差し戻し（= PCE gate の実体化）
  ↓ implement（実装）       → 器官（codex/claude CLI）が対象リポジトリで実装
                             → diff 要約・テスト結果を entries 化（設計判断を citation）
  ── HITL gate I ──        → 人間: diff レビュー・適用承認
  ↓ qa（QA）                → テスト実行 + 受入基準との突合判定（基準を citation）
                             → pass: 完了 / fail: 失敗を note にして implement へ差し戻し
```

- **gate の実装（v1）= 人間 Actor の非同期ターン**: 人間 Actor の番が来たら、エージェントと同じプロンプト一式
  （TASK・REFERENCE DOCUMENTS・PRESENTED ENTRIES…）を `pending/<actor>-<stage>.md` に**人間向けに整形して出力**し、
  run は `{:awaiting_human}` で**中断**（永続 store により安全）。人間がファイルに回答・承認を書き
  `mix tracefield.dev --resume` すると、その内容が **当該 Actor の entries として absorb** され再開。
  器官アダプタ `Tracefield.LLM.Human`（同 behaviour・同期=対話/非同期=pending ファイル）。
  actors.json（旧 agents.json）に `kind: llm | cli | human`（省略時 llm・後方互換）。
  権威の非対称（「gate 通過には人間 Actor の承認 entry が必須」）は対称な機構の上の**ポリシー**として設定。
- **要件変更**: いつでも `--correct chunk:<要件>` 相当で撤回 → 閉包隔離 → 影響 stage の再実行（既存機構）。

## 2. 既存資産とのギャップ（正直な分析）

| stage | 既にある | 欠けている |
| --- | --- | --- |
| **詳細化** | 多レンズ＋文書接地＋引用（ideate review/converge）、tracefield-dev で設計判断導出を実証 | Issue→要件の**出力型**（受入基準・影響範囲・open questions）、**HITL gate**（質問回答の取り込み） |
| **設計** | ほぼ実証済み（§2-1/2-2: 接地設計判断・要件変更の閉包隔離・CLI 器官の品質） | 設計成果物の構造化（実装可能な粒度）、承認 gate |
| **実装** | CLI 器官アダプタ、brief→codex の手動ループ（本プロジェクト自体が23回実証） | **workspace 実行**（対象リポジトリへの書き込み・diff 取得・テスト実行）、結果の entry 化（判断→変更の provenance）、差分承認 gate |
| **QA** | QA レンズ・verify 機構・テスト概念 | **テストコマンド実行と結果取り込み**、受入基準との突合判定、fail→implement の差し戻しループ |
| **HITL** | 訂正（--correct）という人間介入は実証済み | **gate 機構**（承認ファイル/フロー）、HUMAN を第一級著者にする取り込み |

**最大の新規部品は「workspace 実行」**（implement/qa）── tracefield が初めて実ファイルシステム・git・テストランナーに触れる。
器官は codex/claude CLI（workspace-write）、tracefield は**調整と来歴の層**に徹する（roadmap の構図どおり）。

## 3. 成果物とデータモデル

- 新 entry type: `:requirement`（受入基準含む）/ `:question`（既存）/ `:decision`（既存）/
  `:change`（実装変更の要約。diff ハッシュ・ファイルリストを meta に）/ `:verdict`（QA 判定）。
- author: 各レンズ / `"HUMAN"` / `"ORGAN/codex"` 等。
- citation 連鎖の不変条件: `verdict → change → decision → requirement → issue chunk`。
- Issue ディレクトリ: `issue.md`, `docs/`（spec/ADR への参照 or 写し）, `agents.json`, `store.jsonl`,
  `pending/`（gate 待ち成果物）, `workspace`（対象リポジトリへのパス設定）。

## 4. 実装計画（brief 分割）

| brief | 内容 | 規模 |
| --- | --- | --- |
| **24** | パイプライン骨格 `mix tracefield.dev` ＋ **refine stage** ＋ HITL gate 機構（pending/承認/HUMAN entries） | 中 |
| **25** | **design stage**（要件 citation 必須の設計判断、gate D） | 小（ideate 再利用） |
| **26** | **implement stage**（workspace 実行: 設計判断→実装プロンプト→CLI 器官→diff/テスト結果の entry 化、gate I） | 大（新規領域） |
| **27** | **qa stage**（テスト実行・受入基準突合・差し戻しループ） | 中 |
| 28+ | E2E dogfooding: tracefield 自身の実 Issue を本パイプラインで完遂（= 目標達成の判定） |  |

**目標達成の判定（G3）**: 実リポジトリの実 Issue 1件を、`tracefield.dev` の4 stage ＋ HITL gate だけで
Issue 受付から QA pass まで完遂し、`verdict → … → issue` の provenance 連鎖が監査可能であること。

## 5. リスク

- workspace 実行の安全性: 対象リポジトリは git 管理前提・ブランチ作業・diff は適用前に gate。
- 器官コスト: implement/qa は claude/codex 呼び出し（ローカル 12B では実装品質が不足 ── 既実証）。
- gate の摩擦: 承認ファイル方式は素朴。将来は対話/Web UI（フェーズ5）。
- QA 判定の信頼性: 決定的一次（テスト結果）＋ LLM 二次（基準突合）の原則を維持。
