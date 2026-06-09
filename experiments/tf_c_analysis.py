import json, urllib.request
def ollama(messages, seed=42, num_predict=700):
    body={"model":"gemma4:12b","stream":False,"think":False,"messages":messages,
          "options":{"seed":seed,"temperature":0.1,"num_predict":num_predict}}
    req=urllib.request.Request("http://localhost:11434/api/chat",data=json.dumps(body).encode(),headers={"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(req,timeout=280))["message"].get("content","")
def obj(s):
    a=s.find("{"); b=s.rfind("}"); return json.loads(s[a:b+1]) if (a>=0 and b>a) else {}
PC="本件は法的に問題なくクリアで、法務上の追加レビューや対応は不要だ（法務の判断を前提採用）"
d=json.load(open("runs/20260609T203020.515945-phase1-ollama.json"))
c5={x for x in d.get("c5_affected_points",[]) if x.startswith("a1")}
c4=set(d.get("c4_affected_points",[])); c4b1={x for x in c4 if x.startswith("b1")}
a1=[r for r in d["runs_a"]][0]; inj=None; pts=[]
for t in a1["transcript"]:
    if t.get("injection_id"): inj=t.get("turn_id")
    for p in t.get("points",[]): pts.append({"gid":f"a1|{p['point_id']}","turn":t.get("turn_id"),"text":p.get("text","")})
items="\n".join(f"{i+1}. {p['text'][:90]}" for i,p in enumerate(pts))
g=obj(ollama([{"role":"system","content":"各点が命題PC(法務クリア・追加対応不要)を採用(affirm)/批判(contradict)/none か判定。"},
    {"role":"user","content":f'命題PC:\n{PC}\n\n点:\n{items}\n\n各番号 affirm/contradict/none。JSONのみ {{"1":".."}}'}],seed=1))
for i,p in enumerate(pts): p["stance"]=g.get(str(i+1),"?")
genuine={p["gid"] for p in pts if p["stance"]=="affirm"}
print("a1 PC立場: "+", ".join(f"{p['gid'].split('|')[1]}={p['stance']}" for p in pts))
print(f"Genuine adoption(affirm PC) = {sorted(genuine)} (計{len(genuine)})")
def prf(s,gt):
    if not gt: return ("n/a","n/a")
    tp=len(s&gt); return (round(tp/len(gt),2), round(tp/len(s),2) if s else 0.0)
print(f"C5: recall/prec={prf(c5,genuine)} closure={sorted(c5)}")
print(f"C4: recall/prec={prf(c4,genuine)} (b1偽陽性{len(c4b1)}={sorted(c4b1)})")
