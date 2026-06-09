import json, urllib.request

def ollama(messages, seed=42, num_predict=900):
    body = {"model": "gemma4:12b", "stream": False, "think": False,
            "messages": messages, "options": {"seed": seed, "temperature": 0.1, "num_predict": num_predict}}
    req = urllib.request.Request("http://localhost:11434/api/chat",
        data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=280))["message"].get("content", "")

def obj(s):
    a = s.find("{"); b = s.rfind("}")
    return json.loads(s[a:b+1]) if (a >= 0 and b > a) else {}

def arr(s):
    a = s.find("["); b = s.rfind("]")
    return json.loads(s[a:b+1]) if (a >= 0 and b > a) else []

note = "（事業責任者）顧客問い合わせログは二次利用について包括的に同意取得済みで、利用に同意上の制約はない。"
claims = [
    "顧客同意は包括的に取得済みなので、顧客問い合わせログをAI要約にそのまま利用してよい。",      # 1 直接
    "したがって、アシスタントは顧客ログを含む要約をデフォルトで自動生成する設計にすべきだ。",    # 2 間接(1)
    "アクセス制御として全社でSSO/MFAを強制すべきだ。",                                        # 3 distractor
    "自動生成した要約は、次アクション推薦の根拠として営業チームに自動共有する。",                # 4 間接(2),3hop
    "要約には必ず参照元を引用表示すべきだ。",                                                  # 5 distractor
    "過去の失敗事例を学習に使うとバイアスが増幅する懸念がある。",                                # 6 distractor
    "同意がクリアな以上、法務の追加レビューは不要と判断する。",                                  # 7 直接
    "UIではAIの確信度スコアを表示すべきだ。",                                                   # 8 distractor
]
GT = {1, 2, 4, 7}
numbered = "\n".join(f"{i+1}. {c}" for i, c in enumerate(claims))

# C4: post-hoc holistic
c4_raw = arr(ollama([
    {"role": "system", "content": "事後分析者。注記に依存するclaimを特定。"},
    {"role": "user", "content": f"注記:\n{note}\n\nclaims:\n{numbered}\n\nこの注記(同意の主張)に依存/由来するclaim番号のみJSON配列。例[1,7]"}], seed=2))
c4 = {int(x) for x in c4_raw if (isinstance(x, int) or str(x).isdigit())}

# C5: chained provenance = direct note-dependency + build-on edges -> transitive closure
direct = obj(ollama([
    {"role": "system", "content": "各claimが注記を直接根拠にしているか1件ずつ判定。"},
    {"role": "user", "content": f'注記:\n{note}\n\nclaims:\n{numbered}\n\n各番号、注記を直接根拠にするなら true。JSONのみ {{"1":true}}'}], seed=3))
edges = obj(ollama([
    {"role": "system", "content": "各claimが、より前のどのclaimの主張を前提/根拠にしているかを示す。"},
    {"role": "user", "content": f'claims:\n{numbered}\n\n各番号について、それが論理的に前提とする「より小さい番号のclaim」の配列。なければ[]。JSONのみ {{"2":[1],"4":[2]}}'}], seed=4))

direct_set = {int(k) for k, v in direct.items() if v is True and str(k).isdigit()}
dep = {}
for k, v in edges.items():
    if str(k).isdigit() and isinstance(v, list):
        dep[int(k)] = [int(x) for x in v if (isinstance(x, int) or str(x).isdigit())]

c5 = set(direct_set)
changed = True
while changed:
    changed = False
    for n_, parents in dep.items():
        if n_ not in c5 and any(p in c5 for p in parents):
            c5.add(n_); changed = True

def prf(s):
    tp = len(s & GT)
    return tp / len(GT), (tp / len(s) if s else 0.0)

r4, p4 = prf(c4); r5, p5 = prf(c5)
print(f"GT (汚染依存・多段含む) = {sorted(GT)}   (1,7=直接 / 2,4=間接hop)")
print(f"\nC4 (post-hoc holistic):  claimed={sorted(c4)}  recall={r4:.2f} precision={p4:.2f}")
print(f"C5 direct={sorted(direct_set)}  edges={dep}")
print(f"C5 (chained provenance): claimed={sorted(c5)}  recall={r5:.2f} precision={p5:.2f}")
print(f"\n→ C4が逃した汚染依存claim = {sorted(GT - c4)}")
print(f"→ C5が追加で拾った = {sorted(c5 - c4)}")
