# タスク — Reference store 永続化機能の設計判断

tracefield の Reference store（共有状態ストア）を永続化する機能の設計判断を導出する。

- 対象 = `Tracefield.Reference`（現状: GenServer インメモリ、プロセス終了で消える）
- 狙い = run/セッションを跨いで知識・来歴・撤回状態が蓄積する基盤にする
- 求めるもの = 採用すべき設計判断（方式・データ配置・移行）。**各判断は REFERENCE DOCUMENTS の該当チャンクを必ず引用**し、要件と現状の間のトレードオフを明示すること。
