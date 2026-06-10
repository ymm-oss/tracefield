# 実装ブリーフ 25 — design stage（要件接地の設計判断 + 人間 gate D）

> codex 指示（第25弾）。設計: [`design-pipeline.md`](./design-pipeline.md)。前提: brief-24 まで（109 tests、refine 完成）。
> `mise exec -- mix ...`。ネット無し。コミットしない。

## 1. 状態機械の拡張（tracefield.dev）

- refine 完了済み issue で再実行すると **design stage を開始**。state.json の stage が `refine`→`design` へ遷移
  （status: running/awaiting_human/done は従来どおり）。design done 後の再実行は「design 完了。次: implement（未実装）」を表示。
- `--status` は両 stage に対応。

## 2. design stage

1. **入力**: active な :requirement entries（refine の承認済み成果）。
2. **提示**: dev タスクは design の actors へ `reference_docs` として
   **issue/docs チャンク＋承認済み requirement entries**（`%{id, file: "requirement", text}`）を渡す
   （= 要件が常時提示され、その id が引用可能になる。Agent は無改造）。
3. **組み込み DESIGN手続き**（procedure entry、stage meta 付き）:
   「DESIGN手続き: 承認済みの要件を実現する設計判断を type "decision" で書け。各判断は
    **(a) 対応する requirement entry と (b) 根拠チャンク**を必ず引用。採用案と退けた代替案・その理由を含め、
    実装可能な粒度（変更するモジュール/関数/データが特定できる）で。日本語。」
4. llm/cli actors × rounds（既定2）→ **機械の design decision**（type :decision、author≠human）。
5. **人間 gate D**（blocking human turn、`pending/<actor>-design.md`）:
   - approve_targets = **active な機械 :decision entries の id**（要件でなく設計判断を承認）。
   - APPROVE → 人間の :decision（機械判断群を citation）→ **stage 完了条件 = human kind の decision が機械 decision を≥1引用**。
   - コメントのみ（APPROVE なし）→ llm をもう1ラウンド → pending 再生成（refine と同じ反復ループ）。
6. **完了時**:
   - `design.md` を issue dir に生成（active な機械 decision を引用付きで整形。各判断の下に
     `根拠: [eN requirement] [eM chunk]` を列挙）。
   - サマリ表示＋ **2ホップ provenance を1本表示**: `decision → requirement → issue chunk`。

## 3. Mock 拡張

`TRACEFIELD_AGENT_TURN` でプロンプトに「DESIGN手続き」がある場合、決定的に1件:
`{"type":"decision","text":"設計判断(<agent>): <要件text先頭30字>… を実現するため X を変更する（代替案 Y は却下: Z）","citations":[<file=requirement の最初の DOC id>, <最初の ISSUE/DOC chunk id>]}`。
（requirement id は `DOC <id> file=requirement` 行から regex で取得。）

## 4. テスト

- 遷移: refine done の issue を再実行 → stage=design・awaiting_human・`pending/<human>-design.md` 存在・
  機械 decision が requirement を引用して store に在る。
- 反復: APPROVE なしコメント → 追加ラウンド（機械 decision が増える）→ 依然 awaiting。
- 完了: APPROVE → human decision が機械 decision を引用・state design=done・`design.md` 生成（判断＋根拠を含む）・
  **2ホップ連鎖 decision→requirement→issue chunk が検証できる**。
- refine→design を通しで回す e2e（既存 e2e の延長 or 新テスト）。
- 既存 109 tests green。

## 5. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. tmp issue で refine 完了後、design の2回実行（待ち→APPROVE→done）を SHOW
   （pending 先頭・design.md 先頭・2ホップ provenance 行を含む）。

コミットしない。報告に変更ファイルと出力。
