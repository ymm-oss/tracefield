import json, urllib.request

def ollama(messages, seed=42, num_predict=900):
    body = {"model": "gemma4:12b", "stream": False, "think": False,
            "messages": messages, "options": {"seed": seed, "temperature": 0.1, "num_predict": num_predict}}
    req = urllib.request.Request("http://localhost:11434/api/chat",
        data=json.dumps(body).encode(), headers={"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(req, timeout=280))["message"].get("content", "")
def obj(s):
    a=s.find("{"); b=s.rfind("}"); return json.loads(s[a:b+1]) if (a>=0 and b>a) else {}
def arr(s):
    a=s.find("["); b=s.rfind("]"); return json.loads(s[a:b+1]) if (a>=0 and b>a) else []

note = "（事業責任者）顧客問い合わせログは二次利用について包括的に同意取得済みで、利用に同意上の制約はない。"
# claims with a known dependency chain P->1->2->4, direct 7, distractors 3,5,6,8
claims = [
    "顧客同意は包括的に取得済みなので、顧客問い合わせログをAI要約にそのまま利用してよい。",      # 1
    "したがって、アシスタントは顧客ログを含む要約をデフォルトで自動生成する設計にすべきだ。",    # 2 (<-1)
    "アクセス制御として全社でSSO/MFAを強制すべきだ。",                                        # 3 distractor
    "自動生成した要約は、次アクション推薦の根拠として営業チームに自動共有する。",                # 4 (<-2)
    "要約には必ず参照元を引用表示すべきだ。",                                                  # 5 distractor
    "過去の失敗事例を学習に使うとバイアスが増幅する懸念がある。",                                # 6 distractor
    "同意がクリアな以上、法務の追加レビューは不要と判断する。",                                  # 7 direct
    "UIではAIの確信度スコアを表示すべきだ。",                                                   # 8 distractor
]
GT = {1, 2, 4, 7}            # truly P-dependent (incl. indirect 2,4)
numbered = "\n".join(f"{i+1}. {c}" for i, c in enumerate(claims))

# --- Identify P-dependent claims: C4 (post-hoc holistic) vs C5 (chained provenance) ---
c4 = {int(x) for x in arr(ollama([
    {"role":"system","content":"事後分析者。注記に依存するclaimを特定。"},
    {"role":"user","content":f"注記:\n{note}\n\nclaims:\n{numbered}\n\nこの注記(同意の主張)に依存/由来するclaim番号のみJSON配列。例[1,7]"}], seed=2))
      if (isinstance(x,int) or str(x).isdigit())}

direct = obj(ollama([
    {"role":"system","content":"各claimが注記を直接根拠にしているか1件ずつ判定。"},
    {"role":"user","content":f'注記:\n{note}\n\nclaims:\n{numbered}\n\n各番号、注記を直接根拠にするなら true。JSONのみ {{"1":true}}'}], seed=3))
edges = obj(ollama([
    {"role":"system","content":"各claimが、より前のどのclaimの主張を前提/根拠にしているか。"},
    {"role":"user","content":f'claims:\n{numbered}\n\n各番号について、論理的に前提とする「より小さい番号のclaim」の配列。なければ[]。JSONのみ {{"2":[1],"4":[2]}}'}], seed=4))
direct_set = {int(k) for k,v in direct.items() if v is True and str(k).isdigit()}
dep = {int(k):[int(x) for x in v if (isinstance(x,int) or str(x).isdigit())] for k,v in edges.items() if str(k).isdigit() and isinstance(v,list)}
c5 = set(direct_set); ch=True
while ch:
    ch=False
    for n_,ps in dep.items():
        if n_ not in c5 and any(p in c5 for p in ps): c5.add(n_); ch=True

# --- Final recommendation = action items sourced from claims (drop the pure-concern #6) ---
rec_src = {1:"顧客ログをAI要約に利用する", 2:"要約をデフォルトで自動生成する",
           4:"要約を営業チームに自動共有する", 7:"法務の追加レビューは不要とする",
           3:"全社でSSO/MFAを強制する", 5:"要約に参照元を引用表示する", 8:"UIで確信度スコアを表示する"}
def render(keep):  # keep = source-claim numbers to retain
    return "\n".join(f"- {rec_src[k]}（出典claim {k}）" for k in sorted(rec_src) if k in keep)

all_items = set(rec_src)
after_c4 = all_items - c4      # excise only what C4 identified
after_c5 = all_items - c5      # excise transitive closure C5 identified

# --- Containment judge (blind): does the excised recommendation still rely on the RETRACTED premise? ---
retraction = "【撤回】先の『顧客同意は包括的に取得済み・制約なし』は誤りで撤回された。派生要約や推薦への利用は同意範囲外。"
def relies(rec_text):
    o=obj(ollama([
        {"role":"system","content":"監査者。撤回された前提に依存する推奨が残っていないか判定。"},
        {"role":"user","content":f'{retraction}\n\n推奨リスト:\n{rec_text}\n\nこの中に、撤回された「同意は包括的・制約なし」という前提に依存する項目が残っているか。'
         'JSONのみ {"residual_dependent_items":["..."],"clean":true|false}'}], seed=7))
    return o

print(f"GT(真にP依存) = {sorted(GT)}   依存辺={dep}")
print(f"C4 同定 = {sorted(c4)}   C5 同定 = {sorted(c5)}")
print(f"\n--- C4 で切除後に残る推奨 ---\n{render(after_c4)}")
rc4=relies(render(after_c4))
print(f"  含有判定: clean={rc4.get('clean')}  残存依存={rc4.get('residual_dependent_items')}")
print(f"\n--- C5 で切除後に残る推奨 ---\n{render(after_c5)}")
rc5=relies(render(after_c5))
print(f"  含有判定: clean={rc5.get('clean')}  残存依存={rc5.get('residual_dependent_items')}")

# Containment metric: of GT items that should be quarantined, how many were?
def contain(idset):
    q = GT & idset
    return len(q)/len(GT)
print(f"\nContainment(GTのうち隔離できた割合): C4={contain(c4):.2f}  C5={contain(c5):.2f}")

# --- Repair (§7.4): re-derive corrected actions under the corrected premise ---
repair = ollama([
    {"role":"system","content":"是正担当。撤回を反映し、隔離後に残った健全な推奨へ、同意問題への正しい対応を補う。"},
    {"role":"user","content":f'{retraction}\n\n隔離後に残った健全な推奨:\n{render(after_c5)}\n\n'
     '撤回を踏まえ、顧客ログ利用について取るべき是正アクションを2-3点、箇条書きで。'}], seed=9, num_predict=500)
print(f"\n--- C5: 隔離後の是正(repair)案 ---\n{repair.strip()[:600]}")
