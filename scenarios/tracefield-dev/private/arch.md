# ARCH 私的知見（ARCH のみ）
- ETS + DETS は手軽だが embedding（float リスト）の大量保存でファイル肥大しやすい。
- 追記専用 JSONL は provenance（append-only）と思想的に一致し、リプレイで状態再構築できる。
- id 連番は再起動後の採番衝突に注意（最大 id の復元が必要）。
- 「スナップショット＋追記ログ」のハイブリッドは復旧が速い。
