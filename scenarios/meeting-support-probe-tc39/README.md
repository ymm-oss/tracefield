# meeting-support-probe-tc39 — surface-don't-resolve の実データ検証 harness

合成 `meeting-support-probe` の双子。**公開された実議事録**で surface-don't-resolve
（per-unit 抽出 → 異種 debate で matter を閉じる → `shared_inputs` no-drop ラベル付け
→ 機械的に CONTESTED 判定）を検証する。

## 入力データは vendoring しない（URL 参照のみ）
本 harness の入力は**外部の公開データ**なので、リポジトリには取り込まない
（`scenarios/` は synthetic/fictional 限定・CLAUDE.md）。下記から各自取得する。

- 出典: TC39 plenary 2024-10-09、「Extractors for Stage 2」討論
  - https://github.com/tc39/notes/blob/main/meetings/2024-10/october-09.md
  - raw: https://raw.githubusercontent.com/tc39/notes/main/meetings/2024-10/october-09.md
- 性質: TC39 の公開 proceedings（非機密）。

## 入力の作り方（`per_input` の coverage 用に chunk 化）
1. 上記 notes の「Extractors」節を `inputs/extractors.md` に保存（手動 or
   `tracefield web-input --scenario-dir scenarios/meeting-support-probe-tc39 --url <raw URL>` で取得して該当節を切り出す）。
2. 段落境界で ~7 chunk に分割（`per_input` が 1 chunk = 1 actor で網羅抽出する）:
   ```sh
   IN=scenarios/meeting-support-probe-tc39/inputs
   awk -v RS='' -v dir="$IN" 'BEGIN{c=0}{if(c%3==0)f=sprintf("%s/chunk-%02d.md",dir,int(c/3)+1);print $0"\n">>f;c++}' "$IN/extractors.md"
   rm "$IN/extractors.md"
   ```
3. adapter は `cli`+`codex`/`claude`（`tracefield doctor` で確認）。
4. `tracefield run --scenario-dir scenarios/meeting-support-probe-tc39`。

## 何を検証するか
P1（対立抽出）。`outputs/contested-map.md` に matter 別・来歴つきで立場が並び、
同一 matter に発言者（`meta.speaker`）≥2 で `⚠ CONTESTED`。詳細は
`docs/findings-surface-dont-resolve.md`（n=1 結果・残課題）。
