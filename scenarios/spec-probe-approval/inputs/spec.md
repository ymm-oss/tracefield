# 仕様: 重み付き多者承認 `evaluate_approval(doc)`

社内文書の承認判定。**5つの規則が関わる: 重み / 減衰 / 部門上限 / 委任 / 撤回。**
（この仕組みは本システム固有。標準ワークフローではない。）

## データモデル
- `Approver`: `{ approver_id, department, weight }`（`weight` = 役職重み, 正の整数）
- `Approval`: `{ doc_id, approver_id, cast_at }`（誰がいつ承認したか）
- `Delegation`: `{ from_approver, to_approver }`（承認権限の委任）
- `Doc`: `{ doc_id, author_id, status }`

## API
```python
def evaluate_approval(doc) -> bool:   # True = 承認成立
```

## 規則
### しきい値
- 文書は、**有効承認の重み合計が `threshold = 100` 以上**なら承認成立。

### 減衰（decay）
- 各承認の寄与重みは時間で減衰する: `寄与 = weight × max(0, 1 − 0.1 × (今日 − cast_at の日数))`。
  - 例: cast 当日は満額、5日後は半分、10日以降は 0。

### 部門上限（cap）
- **1つの部門が合計に寄与できるのは最大 50（= threshold の 50%）まで。** 超過分は切り捨てる。

### 委任（delegation）
- Approver は自分の承認権限を別の Approver に委任できる。
- 委任された承認は、**委任元(`from_approver`)の weight と department で**数える。

### 撤回（revoke）
- Approver は自分の承認を撤回できる（その `Approval` を取り消す）。

## 戻り値
有効承認の（減衰後・部門上限適用後の）重み合計が `threshold` 以上なら `True`、未満なら `False`。
