# DX 私的知見（DX のみ）
- Reference.start_link の API を変えると ideate/hetero/doseresponse の全タスクに波及する。opts 追加のみが望ましい。
- シナリオごとにストアファイルを分ける（scenario ディレクトリ配下）と運用が直感的（memory/ の前例と揃う）。
- 「--persist-store false」のような明示 opt-out が実験系タスクには必要。
- 移行: 既存の保存済み runs/*.json から store を再構築できると過去資産が活きる。
