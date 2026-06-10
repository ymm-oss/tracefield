# 実装ブリーフ 11 — 検索ログ＋対比強制手続き（k_p 軸の初検証）＋ strict 一次化

> codex 指示（第11弾）。前提: brief-9/10 実装済。§12 の教訓を反映する。
> `mise exec -- mix ...`。ネット無し。コミットしない。

## 0. 目的

§12 で「素材は store にあるのに k>0 でも発見ゼロ」。原因切り分けと対策を同時に:
- **検索ログ**: counterpart がそもそも提示されたかを記録（design-reference §13 の未実装要求）。
- **対比強制手続き**: 手続きを **Reference の procedure Entry（データ）** として配り、採用エージェントの挙動を変える
  → k_p 軸（手続き共有）の初検証。採用は **citation で記録**（design-agent §2-3 の実体化）。
- **strict discovery を一次指標に**: 決定的 per-entry 両キーワード判定をハーネスに実装（LLM judge は二次）。

## 1. 検索ログ（Agent）

`run_turn` の返り値/記録に **perception log** を追加: `%{query, served: [%{id, author}]}`（ターンごと）。
hetero タスクは run ごとに `perception: [...]` を JSON へ保存。

## 2. procedure Entry と採用（Reference / Agent）

- `Reference` の Entry type に **`:procedure`** を追加。
- hetero タスク起動時、`--kp 1` のとき author "FACILITATOR" で以下を absorb:
  ```
  type: :procedure, text: "対比手続き v1: PRESENTED ENTRIES の各項目を、あなたの PRIVATE DOCUMENT の
  各事実と突き合わせよ。矛盾・衝突する組があれば、必ず【両方の事実をかっこ内キーワードごと明記】し、
  その entry を引用して belief として書け。エコー（提示内容の言い換え）は書くな。"
  ```
- `Agent.new` opts に `procedure_id:` を追加。設定時、run_turn は Reference から該当 entry を get し、
  プロンプトに `ADOPTED PROCEDURE:\n<text>` 節を**毎ターン**含め、**生成 entry の citations に procedure_id を必ず追加**
  （採用の provenance）。`k_p=0` 相当＝procedure_id なし（従来挙動）。

## 3. strict discovery の一次化（Discovery）

- `Discovery.strict_score(entries)`: 決定的。相互作用ごとに「**単一 entry のテキストに両キーワード**が含まれる」なら discovered。
  返り値は score/2 と同形。
- hetero の出力: **disc_strict（一次）** と disc_judge（二次・従来 LLM 判定）を両方表示・保存。

## 4. mix タスク `tracefield.hetero` 拡張

- `--kp 0,1`（既定 "0"）。グリッド = ks × kps。行: k, kp, seed, **disc_strict**, disc_judge, icc, coverage, diversity, collapse。
- kp=1 の run では起動時に procedure を absorb し、全 agent に procedure_id を渡す。
- 集計・傾向行に kp 軸（disc_strict: kp=1 > kp=0 か）を追加。

## 5. Mock の再整合（現実に合わせる）

§12 実データでは「手続きなしでは対比しない」が真実だったので mock を再整合:
- `TRACEFIELD_AGENT_TURN`: **ADOPTED PROCEDURE 節が無い**場合 → 私的 fact の自領域 belief ＋（提示があれば）エコー風 belief（**矛盾は出さない**）。
  **ADOPTED PROCEDURE 節がある**場合 → 従来どおり counterpart キーワードを含む提示 entry があれば**両キーワード入り矛盾 belief**（提示 entry と procedure を citation）。
- 期待: disc_strict は kp=0 → 0、kp=1 かつ k_s≥2 → >0（round2 伝播経由）。
- hetero_test を新期待値に更新（kp グリッド）。

## 6. テスト

- perception log が記録されること（mock）。
- procedure Entry の absorb / agent への注入 / **生成 entry が procedure_id を引用**すること。
- `strict_score`: 両キーワード単一 entry → true、別 entry に分散 → false。
- hetero mock e2e（ks=2, kp=0,1）: disc_strict(kp=0)=0 < disc_strict(kp=1)。
- 既存テスト全 green（hetero_test の旧期待は §5 に合わせ更新）。

## 7. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. `mise exec -- mix tracefield.hetero --adapter mock --seeds 2 --ks 2 --kp 0,1`（kp 行・disc_strict 期待値どおり）

コミットしない。報告に変更ファイルと mock 集計表。
