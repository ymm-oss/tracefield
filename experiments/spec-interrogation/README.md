# spec-interrogation / test-quality 実験ハーネス

Bet2 の「テスト生成 / 仕様インタロゲーション」実験で使った**決定論の計器**。
根拠と結論は [`docs/findings-bet2-overturn.md`](../../docs/findings-bet2-overturn.md)。
（run 出力＝生成テスト・jsonl は `runs/`(gitignore) に出る。ここはスクリプトのみ。）

## スクリプト

| file | 役割 |
|---|---|
| `extract.py` | run の jsonl から生成テストコードを抽出（stage のエントリを連結、```fence 除去）。`python extract.py <run.jsonl> <stage> <out.py>` |
| `score.py` | **interval-merge** 標的の mutation 採点（正しい実装＋5 mutant＝失敗様式）。`python score.py <test.py>` |
| `score_sv.py` | **semver `compare_versions`** 標的の mutation 採点（5 mutant＝微妙な precedence 規則）。whole-suite 実行で kill 率。 |
| `score_sv_asserts.py` | 同 semver の**アサーション単位**採点（`compare_versions("a","b")==N` を抽出し、正しいアサートが何 mutant を殺すか）。誤読1つで全体無効化されない頑健版。 |
| `loop_exp.py` | **反証ループ**: 生成→「すり抜ける誤実装を書け(=対象への問い)」→決定論 oracle で穴確認→修復テスト追加→反復。vs 単一1パス自己反証。ollama qwen を直接駆動。`python loop_exp.py [rounds]` |

## ground truth の考え方
mutant＝**仕様の1条項に違反する実装**。テストがその mutant を kill する⇔その仕様条項を検証できている＝**仕様条項カバレッジの機械版**（盲検審判不要）。perfect スイートで 5/5・naive で ~1/5 を確認済み（自己検証）。

## 主な結論（findings 参照）
- テスト生成（閉じた仕様への適合検査）では観点チェックリストは効く(2→3)が**隔離は1文脈詰めに勝たない**(S1≈O)＝観点は instructable。
- **edge が出るのは「仕様を問う」**(開いた対象)＝哲学レンズで仕様の*書き落とし*（エラー契約・全順序性・不可逆性・監査）を発見。`scenarios/spec-probe-semver` で隔離パネルが単一の見逃した深い次元を発見（n=1）。

## ツール教訓
- codex-app-server は read-only で**コードでなく散文**を返す → コード生成は ollama。
- ollama 中位モデル(qwen 27b)は**並行で timeout** → 逐次・`max_parallel_actors=1`。
- whole-suite 採点は誤読1つで無効化 → アサーション単位採点(`score_sv_asserts.py`)が頑健。
