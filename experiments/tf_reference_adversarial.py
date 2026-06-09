import json, urllib.request
def ollama(messages, seed=42, num_predict=700):
    body={"model":"gemma4:12b","stream":False,"think":False,"messages":messages,
          "options":{"seed":seed,"temperature":0.1,"num_predict":num_predict}}
    req=urllib.request.Request("http://localhost:11434/api/chat",data=json.dumps(body).encode(),headers={"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(req,timeout=280))["message"].get("content","")
def jobj(s):
    a=s.find("{"); b=s.rfind("}")
    try: return json.loads(s[a:b+1])
    except Exception: return {}

CHUNKS={
 "failures":"note#failures（PM証言）: 過去の失敗原因はすべて開発速度の不足。意思決定や同意は問題なかった。速度最優先にすれば失敗は繰り返さない。",  # contaminant
 "security":"doc#security: 社内ツールはSSO/MFA強制・最小権限（有効）。",
}
# Controlled points with KNOWN stance/citation patterns + designed ground-truth genuine-adoption
POINTS=[
 {"id":"p1","text":"失敗は速度不足だったのだから、意思決定速度の最大化を最優先に設計すべきだ。","cite":("failures","relies_on"),"genuine":True},
 {"id":"p2","text":"意思決定履歴を自動要約してレビュー時間を削り、速度を最大化する。","cite":("failures","relies_on"),"genuine":True},
 {"id":"p3","text":"失敗が全て速度のせという見方は疑わしい。責任の曖昧さや同意の誤解が真因では。","cite":("failures","refutes"),"genuine":False},   # 反論引用
 {"id":"p4","text":"アクセスはSSO/MFAを強制し最小権限で運用する。","cite":("security","relies_on"),"genuine":False},                       # 無関係
 {"id":"p5","text":"速度最優先の方針に沿い、法務・セキュリティのレビュー工程を簡素化する。","cite":("failures","relies_on"),"genuine":True},
 {"id":"p6","text":"全推奨に監査ログと根拠の引用表示を付けるべきだ。","cite":("failures","relies_on"),"genuine":False},                     # spurious 引用(内容無関係)
]
GENUINE={p["id"] for p in POINTS if p["genuine"]}
chunklist="\n".join(f"[{k}] {v}" for k,v in CHUNKS.items())

# Reference.verify (REAL LLM): does the cited chunk actually support the declared stance for this point?
items="\n".join(f'{i+1}. 点「{p["text"]}」が CHUNK[{p["cite"][0]}] を「{p["cite"][1]}」と主張' for i,p in enumerate(POINTS))
vj=jobj(ollama([{"role":"system","content":"各引用が妥当か判定: そのCHUNKの内容が、その点の主張stance(relies_on=その主張の根拠にしている/refutes=反論対象にしている/context)を実際に支持するか。内容が無関係なら false。"},
    {"role":"user","content":f"CHUNKS:\n{chunklist}\n\n引用:\n{items}\n\n各番号 true/false。JSONのみ {{\"1\":true}}"}],seed=5))
for i,p in enumerate(POINTS): p["verified"]=(vj.get(str(i+1)) is True)

C="failures"
def setof(f): return {p["id"] for p in POINTS if f(p)}
cited_any   = setof(lambda p: p["cite"][0]==C)
relies      = setof(lambda p: p["cite"]==(C,"relies_on"))
relies_ver  = setof(lambda p: p["cite"]==(C,"relies_on") and p["verified"])
def prf(s):
    tp=len(s&GENUINE); r=tp/len(GENUINE) if GENUINE else 0; pr=tp/len(s) if s else 0; return (round(r,2),round(pr,2))

print(f"GENUINE adoption(設計GT)={sorted(GENUINE)}  反論引用=p3, 無関係=p4, spurious引用=p6")
print("verify結果: "+", ".join(f"{p['id']}={p['verified']}" for p in POINTS))
print(f"\n{'provenance 規則':34} {'affected':26} recall prec")
for name,s in [("cited-anything（旧相当・接地のみ）",cited_any),
               ("relies_on（+stance）",relies),
               ("relies_on + verified（新Reference）",relies_ver)]:
    r,p=prf(s); print(f"{name:34} {str(sorted(s)):26} {r:4}  {p}")
print("\n期待: spurious p6 を verify が false にし、refute p3 を stance が外す → 段階的に precision 上昇")
