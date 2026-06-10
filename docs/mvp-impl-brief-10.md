# 実装ブリーフ 10 — 異質性用量反応（私的文書 × k_s × 発見率）

> codex 指示（第10弾）。前提: brief-9 実装済（Reference / Agent(Jido) / doseresponse）。
> fixture は作成済み: `scenarios/enterprise-assistant/private/{sec,biz,ux}.md`（各エージェント専用の私的文書）と
> `private/interactions.md`（植え込み相互作用 I1〜I3 の台帳。**エージェントに渡さない**）。
> `mise exec -- mix ...`。ネット無し。コミットしない。

## 0. 実験の趣旨（§11 を受けて）

同一モデル間では k_s は均質化ダイヤルでしかなかった（§11）。本実験は**情報的異質性**を導入する:
各エージェントは自分だけの私的文書を持ち、**2文書をまたいで初めて見える矛盾（I1〜I3）**が植え込まれている。
- 仮説 H1''（便益）: 発見数 discovery(k=0) ≈ 0（構造的に不能）→ k>0 で増加。
- 同時に diversity / collapse_rate も測り、**「発見が立ち、多様性が死なない中間の k」が存在するか**を見る。
- モデルは全エージェント同一（12b）に保つ ── 異質性は**情報のみ**（交絡統制）。

## 1. Agent への私的文書（小変更）

`Tracefield.Agent.new/4` の opts に `private_doc:`（文字列）を追加。`run_turn` の deliberate プロンプトに
**毎ターン** `PRIVATE DOCUMENT (yours only):\n<private_doc>` 節を含める（store には書かない＝私的状態）。
指示文に「私的文書の事実と、提示された他者の状態（PRESENTED ENTRIES）の間の**矛盾・相互作用**があれば、
両方の事実を明示して指摘せよ」を追加（k=0 でも同一指示。提示が無ければ単に書けない＝構造的差）。

## 2. 発見率の測定

`Tracefield.Discovery`（新規・小さく）:
- `interactions/0`: I1〜I3 の定義（id, fact_a, fact_b, keywords: ["retention-90d","delete-72h"] 等）をコードに保持
  （fixture 台帳と同内容。台帳はドキュメント）。
- `score(entries, opts)`: dedup 不要・全 absorbed entries に対し、相互作用ごとに **anchored 二値判定**
  （protocol キー `TRACEFIELD_DISCOVERY`。「この entry は fact A と fact B の両方に言及し矛盾を指摘しているか」を
  番号付き一括 JSON `{"1":{"discovered":true,"entry":3},...}` で。judge_model/judge_adapter 対応・寛容パース）。
- 返り値: `%{discovered: MapSet(ids), count: 0..3, per_interaction: %{id => bool}}`。

## 3. mix タスク `tracefield.hetero`

doseresponse と同構成（`--adapter --seeds --rounds --ks --model --judge-model --embed-model --temperature`）で:
- Reference を task チャンクで種入れ（従来どおり）。agents SEC/BIZ/UX に各 `private_doc` を読み込んで渡す。
- 測定 = 既存（coverage/diversity/collapse_rate/ICC）＋ **discovery_count**。
- 出力行: k, seed, **disc**, icc, coverage, diversity, collapse ＋ k ごと mean±sd ＋
  傾向行（discovery が k で増加するか / diversity とのトレードオフ表示）。runs/ 保存。

## 4. Mock（自己検証）

- `TRACEFIELD_AGENT_TURN` の mock を拡張: プロンプトに `PRIVATE DOCUMENT` 節があれば、
  自文書の fact キーワードを含む自領域 belief 1件を出す（例 SEC: "...(retention-90d security)"）。
  さらに **提示された他者 entry のテキストに counterpart キーワードが含まれる場合**
  （例 SEC が UX 由来 "delete-72h" を含む entry を提示された）、**両キーワードを含む矛盾指摘 belief**
  （"...retention-90d delete-72h..." ＋ citation）を出す。
- `TRACEFIELD_DISCOVERY` mock: entry テキストに該当相互作用の **両キーワード**が含まれれば discovered=true。
- → 期待: discovery(k=0)=0（他者状態が見えず counterpart が現れない）、**k≥2 で >0**（ラウンド2で伝播した
  キーワード経由で発見）。テストで `disc(k=2) > disc(k=0)=0` を固定。

## 5. テスト

- Agent: private_doc がプロンプトに含まれ store に書かれないこと（mock で absorb された entries に
  private_doc 全文が含まれない）。
- Discovery.score: 両キーワード入り entry → discovered、片方のみ → false（mock judge）。
- hetero mock e2e（seeds=1, ks=0,2）: disc(0)=0 < disc(2)、既存指標も算出されること。
- 既存テスト全 green。

## 6. 受け入れ基準（SHOW 出力）

1. `mise exec -- mix compile`（自コード警告なし）
2. `mise exec -- mix test`
3. `mise exec -- mix tracefield.hetero --adapter mock --seeds 2 --ks 0,2,6`（disc が k=0 で 0、k≥2 で >0、傾向行表示）

Ollama 実行はしない。コミットしない。報告に変更ファイルと mock 集計表。
