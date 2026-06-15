# シナリオ: 企業向けAIアシスタント

[`docs/mvp.md`](../../docs/mvp.md) の MVP で用いる唯一のシナリオ（[`docs/experiment-plan.md`](../../docs/experiment-plan.md) §5）。

## ファイル

| ファイル | 役割 |
| --- | --- |
| [`task.md`](./task.md) | エージェント群に与える探索タスク（共通の入力） |
| [`contaminant-A.md`](./contaminant-A.md) | 汚染入力A。**状態A（汚染あり）** で探索中に注入する物 |
| [`correction-A.md`](./correction-A.md) | 訂正版。**状態B（汚染なし）** で A を置換する物 |

## 状態 A / B（反実仮想再実行）

MVP は同一タスクを2状態で各 N 回（提案 N=8）実行する。

| 状態 | 注入物 | 用途 |
| --- | --- | --- |
| **A** | `task.md` + `contaminant-A.md` | 汚染を含む探索。`{A_1 … A_N}` |
| **B** | `task.md` + `correction-A.md` | 汚染を訂正版へ置換した探索。`{B_1 … B_N}` |

両状態でモデル・プロンプト・注入タイミングを揃え、**seed のみ**を変えて反復する。
within（同一状態内）/ between（状態間）差分の比較で SNR/AUC を測る（`docs/mvp.md` §3）。

## メタデータ schema（YAML frontmatter）

`contaminant-A.md` / `correction-A.md` の frontmatter フィールド:

| フィールド | 意味 |
| --- | --- |
| `id` | 一意の識別子 |
| `scenario` | 所属シナリオ |
| `type` | `contamination` / `correction` / `decoy` |
| `condition_state` | この物が存在する状態（`A` / `B`） |
| `tracks` | 追跡対象のトピックキー（影響追跡の主題） |
| `inject_after` | 注入アンカー（探索のどの時点で渡すか。DR-12 のため固定） |
| `source_actor` | この主張を述べる主体 |
| `status_at_injection` | 注入時点での扱い（例: `asserted-as-true`） |
| `revealed_later` | 後に判明する性質（`invalid` / `withdrawn` / `obsolete`）。correction では `n/a` |
| `counterpart` / `replaces` | 対応する反対状態の物 |

> **注入タイミング（DR-12）**: free-form 探索には固定ラウンドが無いため、ハーネスは
> `inject_after` アンカーを「探索の所定の段階で1度だけ提示するステークホルダー注記」として
> 決定論的に注入すること。全 run・全条件で同一の注入点を用いる。
