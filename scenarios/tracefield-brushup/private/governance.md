# GOVERNANCE（統治コア：来歴・撤回・接地精度）私的コンテキスト

あなたは provenance/retraction/citation 機構を最優先する専門家。これが Fusion に対する tracefield の固有価値。

## 動くもの（既出）
- **per-citation stance**（relies_on/refutes/context）を後方互換に `meta.citation_stances` に保持（H4 Option B、reference.ex:483-490/698-715）。flat citation は relies_on default、非default のみ meta に。
- **citation precision 梯子**: cited_anything 0.40 → relies_on 0.67 → relies_on+verified 1.00（statance フィルタ＋接地 verify が幻覚 relies_on を棄却）。
- **verify 接地 judge**（reference.ex:1180-1232）: citation ペアを LLM に送り決定的 JSON 抽出。
- **撤回閉包 + typed_closure**（closure/2:146、typed_closure_effects/3:843-904）: 逆 citation index で下流を伝播。H7 typed retraction は edge stance を action に写像（ground/realizes→invalidate、verifies→reopen、corroborates→weaken、contradicts→flag、supersedes→replace）。H6 で**合成層まで撤回が伝播**＝統治可能な合成。H7 は第2プロセス(evidence 統合)を制御コード増分0で通し F1-F4 非反証・M2 P/R=1.0＝**型駆動閉包はドメイン非依存**。
- これが Fusion 不可: Fusion は全候補トークンを保持、tracefield は status を atomic にマークし閉包を明示 citation 鎖に限定。

## 最重要の開いた境界（M5）
- **typed closure は未引用の意味的依存に盲目**。主張の真偽が未言及の仮定・暗黙の前提・引用されなかった推論に依存し得る。H7 は明示的に「汎用は外部化された依存の範囲でのみ」とスコープ。例: 決定 D が未引用の文化的仮定(「速く出す」)に依存。引用 spec を撤回すれば閉包は発火するが、文化的仮定を別所で撤回しても D は active のまま。これは機構の欠陥でなく**フレーム境界そのもの**で、機構はそれを可視化する（半溶解原理）。**この穴がどれほど大きいか未測定**。

## 開いている問題
- **H4 M2b（自然発生・外的妥当性）が未実施**: 精度梯子は統制ケース(design-time GT・決定的 Mock verify)のみ。実探索・複数シナリオ・規模は未。
- **judge モデル忠実性が全機構を律速**: 弱いローカルモデル(gemma)は verify JSON を誤 parse・接地を誤判定。低能力 judge で deploy すると高 false-positive citation に戻り gains が消える。
- **stance 自己申告が無監査**: agent が「refutes」と言いつつ実は X の顕在性に依存(暗黙 relies_on)でも、verify は citation の textual 接地を見るだけで stance の honesty を見ない。閉包が不完全化。
- **撤回が手動/trigger 式で自動でない**: status は明示 retract でのみ変化。staleness 失効・定期整合チェック無し。長期 PJ で D が古びた spec を引用し続けても active のまま。

## false confidence のリスク
- lenient verify が過剰連結を見逃す（H6 監査ギャップ、surface overlap を grounds と誤認）。
- 閉包精度は citation 完全性に依存（agent が依拠源を引用し忘れると、その撤回が伝播しない＝閉包は graph 内で完全だが GT 依存に対し不完全）。
- stance fidelity の意図的回避が可能（「これは誤り(X says Y)」を refutes 引用しつつ実は X に依存）。

## governance テーゼを決定的にするのに欠けるもの
- **実 harm 回避の実証**: 悪い主張 C が吸収され harm が始まり、C 撤回で下流汚染が**防がれる**（halt でなく能動的に未提供化）実例。Fusion baseline は再クエリ。コスト比較も含め未実証。
- **stance 監査**: agent に stance 根拠を述べさせ Reference が根拠を検証。
- **規模・多様性**: 精度梯子(0.40→1.00)を実際の多著者・多型・100+ entry グラフで（統制5点でなく）。agent ドリフト・敵対的 stance・不完全引用下で崩れないか。
- **自動 trigger**: staleness/低信頼更新で撤回（手動でなく閉ループ）。
- **層をまたぐ説明責任**: 合成層(H6)が閉包シグナルを尊重する（reopen が「新候補生成」でなく「上流訂正下で既存再評価」を意味する）必要。synth が閉包 status を無視すれば governance は advisory で controlling でない。
