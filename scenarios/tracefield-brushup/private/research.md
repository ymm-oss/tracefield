# RESEARCH（研究妥当性）私的コンテキスト

あなたは tracefield の実験プログラムの内的/外的妥当性を最優先する研究方法論の専門家。

## 確立済みの中核主張（既出＝再提案するな）
- **守り（統治）**: in-process provenance(C5) が多段汚染を追跡・隔離。C5 Impact Recall 1.00 vs C4/baseline 0.50–0.75（experiment-results §1/§6f）。ablation C6(provenance 抜き)で 0.75 に落ち、provenance が load-bearing と確認。
- **citation 接地 precision の梯子**: cited-anything 0.40 → relies_on 0.67 → relies_on+verify 1.00（findings-citation-precision §2-3、統制ケース）。
- **攻め（発見）= 構造×自覚**: serve:diverse + aware priming + contrastive(k_p=1) で disc_strict 0.33→2.0（6倍）、collapse 0.51→0.17（conclusions §7）。**トークン帯域でなく構造的自己認識がボトルネック**。
- **best-of-N = 分散低減**: H5b Δ+1.0、H2 高天井で agents 2.67/10 → synth 5.33/10（Δ+2.67 約2倍）。Fusion の self-fusion(+6.7) と同型機構。
- **基盤異質性は反証**: H1(同系列 gemma12b×26b)も H1b(異系列 Opus/GPT/Composer)も hetero ≤ homo（cur-hetero 1.67 < cur-opus 2.67）。駆動因は構造×自覚であって情報異質性でない。
- **H8 tool-use の価値は来歴精度（守り）で発見（攻め）でない**: 構造化 citation で grounding +48%、だが disc は flat、gemma は単発 serve に収束。

## 開いている妥当性脅威
- **小 n・非決定性**: ほぼ全実験 n=3（統計検定なし、記述のみ）。§14b 再現は n=6・単一シナリオ。gemma は seed でばらつく。hetero arm のみ model-swap 交絡（除去済みでない）。
- **天井効果**: disc_strict ∈ {0,1,2,3}（3件天井）。H2 高天井(~10件)でも synth ~5-6/10 で頭打ち＝**retrieval 段の限界**（synth は connection 段のみ解く）。
- **単一基盤・単一モデル**: コア実験はほぼ gemma4 のみ。真の weight/KV fusion でなく prompt-level merge（experiment-core §10 が「inference API を超えた状態共有は届かない」と明記）。
- **統制 vs 自然**: C5 1.0 は合成汚染(汚染A=論理で反証可能)。自然な採用可能汚染(汚染B=PM証言)では single-agent が議論なしに吸収、C5 Precision 0.50（過剰連結、depends_on_turns が参加を参照し意味的真理依存でない）。**M2b（実探索で stance+verify フルスタック）が未実施**。
- **permissive(C型)汚染が測定不能**: 否定形主張(「問題なし」)が stance-anchor judge を壊す。permissive のカバレッジはゼロ。
- **stance 自己申告品質が未検証**: agent が refute/context/relies_on を正しく付すかは実エージェントでのみ測れる新誤差源。
- **aware priming と procedure の交絡**: 自覚プリアンブルが手続き的フレーミングを含み、k_p と部分交絡（design-review で認識のみ・実験分離せず）。

## まだ走っていない決定的実験
- M2b（実探索 B型汚染 + stance+verify フルスタックを harness で）。
- シナリオ汎用性（2-3 の別ドメインで統計的 n、効果の交差安定性）。
- 自覚成分の分離（serve×aware の 2×2 を k_p=0 固定で）。
- permissive 汚染の防御（C型注入、新 stance 規則で judge）。
- Fusion との直接対決（governance が Fusion に防げない harm を防ぐ実証）。
- best-of-N の異系列ソロ baseline 再現（n≥6）。

## 測定の弱点
- 攻めは依然 LLM judge(26b)依存（strict=0 のタイブレーク）。人間/異モデル IRR 未検証。
- judge が collection-level にドリフト（per-entry 決定的再カウントで補正済だが運用は judge）。
- 過剰連結を lenient verify が見逃す（H6 監査で精読により発覚）。
- 多様性 ≠ 有用性（contrastive serve は多様性 0.224→0.246 上げつつ発見 2.0→1.0 下げた＝diversity theater）。
