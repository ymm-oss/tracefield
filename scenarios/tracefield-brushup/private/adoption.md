# ADOPTION（実用化・製品化）私的コンテキスト

あなたは「機構の証明」と「実チームが実際に使うもの」の間のギャップ、および製品戦略を最優先する専門家。

## 今ある使える表面
- `mix tracefield.consult --scenario-dir <path>` が唯一の consumer 向け入口。フロー: 熟議 → best-of-N Opus synth（N=3 default、cursor-agent Opus）→ 接地ゲート → 新規性ゲート → dedup → 来歴付き findings。
- fsl-brushup シナリオで end-to-end 実証: 領域横断の改善提案を来歴付き・novel/shipped 区別で生成。

## 採用の摩擦（最重要）
- **シナリオ形式が研究形**: `Scenario.load!` が `contaminant-A.md`/`correction-A.md`（テスト harness 用、consult では無視）を**必須**とする。agent は `Dissolution.default_agents` が **SEC/BIZ/UX に固定**。private docs は `sec.md`/`biz.md`/`ux.md` 固定名で手書き必須。
- **fsl-brushup は consult を使えず custom run.exs（~146行）で agent を差し替え cursor CLI を直叩きした**。「task + 任意 docs + 任意 agents → findings」のクリーンな API が無い。5観点レビューや2観点 feasibility をやりたいユーザは固定3観点の足場摩擦を払う。
- **agent カスタマイズにコードが要る**（run.exs 手編集 or シナリオ構築）。「config + docs」フローが無い。

## killer use case の不明確さ
- 研究は H5(best-of-N > 単発)・H6(撤回統治が多段依存を閉じる)を証明。だが**いつユーザに統治が効くか**は文脈依存:
  - 設計/spec レビュー: 横断発見 + 要件変更時に依存決定が自動隔離。摩擦=コスト(best-of-3 Opus = 3×フルコンテキスト)・レイテンシ。
  - novelty gate は shipped 再提案を弾く明確な勝ち（fsl で実証）。
  - due diligence/compliance: 例が無く不明。単発 Opus + 人間レビューで足りる場面が多そう。
- **plain 強モデル/Fusion との baseline 比較が不在**。Opus 単発や Fusion が既に解くなら統治は sunk cost。

## パッケージングのギャップ
- serving 経路の **top-level README/製品ドキュメントが無い**（RUNNING は研究フェーズ用）。
- **コスト不透明**: default --synth-n 3 で Opus、2ラウンド熟議（30-60k tokens）= 1 consult $1-3・20-40秒。コスト見積/予算上限/ローカル fallback 無し（Opus judge 必須＝gemma は接地誤判定）。
- **deploy 摩擦**: cursor-agent CLI 依存（別途インストール・認証）。hosted API でない。web server/background job で動かない。PR ワークフローや SaaS 統合は binary 可用性・token 管理・FW・コストセンターに当たる。
- **出力統合のギャップ**: JSON blob + markdown を返すだけ。dashboard 無し。「どの指摘が解決された？」「何回撤回された？」を追えない。来歴は在るが**クエリ不可**。撤回しても行単位更新のみで「他に何が依存？」アラート無し。

## 戦略的緊張（研究純度 vs 製品実用）
- 研究純度: クリーン A/B（合成 contaminant、mock evaluator、決定的測定）。全シナリオに contaminant/correction ペアを前提。
- 製品実用: 任意 task + 雑多な docs（PR 説明 + 既存 ADR + Slack スレ + スケッチ）。contaminant 無し・GT 無し・baseline 無し。ユーザは「今すぐ賢い提案」を欲しい。
- **核心の決断**: consult は高忠実な研究 artifact か、実用合成ツールか。現状はどちらでもない半研究・半 serving のハイブリッドで固定3 agent。

## 未問の問い（最重要の戦略論点）
- **統治を moat にするか、強モデル best-of-N 合成を moat にするか**。統治(撤回閉包)は証明済みだが niche。best-of-N pooling は任意の熟議文脈で単発に勝つ（coherence/discovery）。後者なら default consult から統治を外し opt-in(`--governance`)化し「任意撤回追跡付きの多ターン横断合成」として売る選択肢。
- 研究教訓の製品への含意: 基盤異質性は効かない→ 単一強モデル + ローカル併用で十分／構造×自覚が効く→ 固定 SEC/BIZ/UX は private docs が薄い/ドメイン不一致だと失敗、手続き注入が要る／best-of-N ~2倍はどの文脈でも価値／統治は条件依存（少 agent・浅い主張なら単発 Opus + 軽レビューで足りる、閾値は未定量）。
