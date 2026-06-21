# 仕様: 注文チェックアウト `checkout(cart)`

EC サイトの注文確定フロー。**3つの部分が関わる: カート / 在庫 / 決済。**

## データモデル
- `Cart`: `{ customer_id, items: [{ sku, qty }] }`
- `InventoryItem`: `{ sku, unit_price, stock }`（`stock` = 在庫数）
- `Order`: `{ order_id, customer_id, items, total, status }`
- `Payment`: `{ order_id, amount, status }`

## API
```python
def checkout(cart: Cart) -> Order:
```
チェックアウトは次を順に実行する:
1. **カート検証**: `items` が空でない／各 `qty >= 1`／各 `sku` が存在する。`total = Σ(unit_price × qty)` を計算する。
2. **在庫確保**: 各 item について `InventoryItem.stock >= qty` を確認し、`stock` を `qty` だけ減算する。
3. **決済**: 顧客のカードに `total` を請求する（決済 API が 成功/失敗 を返す）。
4. **注文作成**: `status = confirmed` の `Order` を作成して返す。

## 各部分の規則
### カート
- 空カートは拒否。`qty < 1` は拒否。存在しない `sku` は拒否。
- `total` は各 `unit_price × qty` の総和。

### 在庫
- `stock` が `qty` に満たない `sku` があれば、その checkout は**在庫不足**で失敗する。
- 在庫確保は `stock` を即座に減算する。

### 決済
- 決済 API が**失敗**を返したら、checkout は**決済失敗**で終わる。
- 請求金額は `total` に一致する。

## 戻り値
成功時は `status = confirmed` の `Order`。失敗時は対応するエラー（カート不正 / 在庫不足 / 決済失敗）。
