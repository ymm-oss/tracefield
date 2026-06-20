#!/usr/bin/env bash
# 検証済み FSL synthesis を最終 .fsl として FSL リポジトリに配置する（決定的・placement のみ）。
# fslc ゲートは flow 内の [stages.fslc_gate] が実行済（run の fslc_gate observation / meta.exit_code を見よ）。
# 調査段は read-only。エージェントにファイルを書かせず、ここで決定的に書き出す（中核の provenance/監査を壊さない）。
#
# Usage: ./realize.sh <run.jsonl> <out.fsl>
#   <run.jsonl>  `tracefield run --persist` で永続化したフロー実行
#   <out.fsl>    出力先（例: <fsl>/specs/store_status.fsl）
set -euo pipefail
run="${1:?usage: realize.sh <run.jsonl> <out.fsl>}"
out="${2:?usage: realize.sh <run.jsonl> <out.fsl>}"

# ASSEMBLE synthesis の ```fsl フェンス内だけを決定的に抽出（散文の監査はフェンス外＝除外）。
jq -r 'select(.author=="ASSEMBLE" and .type=="synthesis") | .text' "$run" \
  | awk 'BEGIN{f=0} /^```fsl/{f=1;next} /^```/{f=0;next} f' > "$out"
[ -s "$out" ] || { echo "realize: ASSEMBLE synthesis に \`\`\`fsl ブロックが無い ($run)" >&2; exit 2; }
echo "realize: wrote $out"
echo "  （fslc ゲートは flow 内で実行済。赤なら run の fslc_gate エントリ/meta.exit_code を出典に再起草してフロー再実行）"
