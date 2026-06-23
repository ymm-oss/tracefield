# meeting-support-probe — surface-don't-resolve の計器

定例MTGの議事録/チャット＋方針ブリーフから「対立マップ」と「進め方」を出す
surface-don't-resolve フローの **計器（probe instrument）**。データは架空。

## 正直な制約（先に読む）
このシナリオは **machinery（配線）を検証する計器** であって、feasibility の *判定*
そのものではない。本番の判定には (1) 実 prep の実データ、(2) コンサルが AI 出力を見る
*前*に書いた「意図したデッキ/進め方」（事前登録）、が要る。合成データを自分で作って
自分で採点すると偽の信号になる（自分の宿題を自分で採点しない）。よってこの harness は
「実データが来た瞬間に本番が回る状態」を作るためのもの。

## フロー（surface-don't-resolve）
`stances`(grounded・per_input で各資料を隔離読み) → `verify_stances`(per_input・*妥当性*のみ反証)
→ `adjudicate_stances`(retract_overturned) → `foresight`(STAKEHOLDER/READINESS/FRAMING)。
終端は判定 collapse でなく artifact 2本:
- `outputs/contested-map.md`（format=`contested_map`）— 論点(matter)別に全立場を来歴つき・無落としで提示、2者以上で `⚠ CONTESTED`。**AI は立場の優劣を決めない**。
- `outputs/how-to-proceed.md` — 次に議論すべき点・誰に聞くか・表現・順序。

verify/adjudication が裁くのは *stance の妥当性*（誤帰属/陳腐化/出典不支持）だけ。
**faithful な立場の対立は触らず Active のまま** contested-map に残る（finding(3)=同一モデルが
好む立場だけ残す偽収束を踏まないための分離）。

## 実行
```sh
# machinery smoke（mock・モデル不要）
./target/release/tracefield run --scenario-dir scenarios/meeting-support-probe

# 実出力（本人の codex/claude）: flow.toml の [organs.reasoning] を1行差し替え
#   adapter = "cli"   command = "codex"      # or "claude" / "cursor-agent"
./target/release/tracefield run --scenario-dir scenarios/meeting-support-probe --persist out.jsonl
```
mock では stance の中身は出ない（配線の確認のみ）。`meta.matter` でのグループ化や
CONTESTED フラグの描画ロジックは `tracefield-core` の単体テストで検証済み。

## 3アーム protocol（実データが揃ったら）
入力を変えて3回回し、`contested-map.md` は不変・`how-to-proceed.md` の差分を見る
（ブリーフは抽出でなく*進め方*を条件付ける）。
- **arm A**: `private/` を空に（議事録/チャットのみ）。foresight が照準を持てるか＝ベースライン。
- **arm B**: `private/agenda-brief.md` のみ投入 → **P2(destination) を分離**（目的を知れば先読みは直るか）。
- **arm C**: `agenda-brief.md` ＋ `political-facts.md` → **P1(対立の機微) を分離**。

計装（これが無いと測れない）:
- **事前登録**: コンサルが AI 出力を見る前に「意図したデッキ/進め方」を書く（anchoring 殺し）。
- **分割採点**: structural fidelity（agenda の形・話す順＝P2）と political framing（対立の表現＝P1）を別計上。
- **時間/コスト**: ブリーフ執筆時間＋提示後に対立を解決する時間 vs 現状の artifact archaeology 時間。

## 先読み deepen-loop arm（P2 の深さを測る・実験）
`flow.toml` の foresight は単発パネル（一次の考慮）。`flow.loop.toml` は同じパネルを
**「刈りながら深める」ループ**にした変種（foresight⇄critique⇄adjudicate(retract) を3周、
自己参照で二次・三次の依存連鎖を掘る）。P1(対立抽出)は両者同一・単発。
```sh
./target/release/tracefield run --scenario-dir scenarios/meeting-support-probe \
  --config scenarios/meeting-support-probe/flow.loop.toml
```
測るのは「単発パネル vs ループ」で **二次・三次の先読み（依存連鎖）が増えるか**。2点厳守:
- **equal-compute で比べる**: ループは foresight 約3周×3レンズ＋刈り＝単発の数倍 compute。フェアには baseline(flow.toml)の foresight を同 compute まで広げる（count を上げる／同観点を1文脈に渡す arm-W）。**信号は深さであって出力量ではない**。
- **kill**: ループが generic に再収束したら（前周の言い換えが増えるだけ）負け。long_run/denoise は answer-quality が equal-compute 未検証の最前線（skill 明記）＝「勝てる」前提で使わない。agenda(private)を勾配にしないと空回りする。

## 読み方（feasibility の核）
prep 時間を支配するのが **retrieval（探索・突合）** なら surface-don't-resolve が勝つ
（提示が探索を潰し、判断は人間に残る）。**judgment（判断）** が支配なら提示は archaeology を
adjudication に移すだけで負け。kill: (a) judgment が retrieval を支配 / (b) ブリーフを流れの中で
書けない（elicitation 摩擦）/ (c) arm B で先読みが直らない（＝P2 は目的不在でなく推論ギャップ→
直交 foresight レンズの増強が要る）。
