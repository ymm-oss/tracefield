import json, urllib.request
def ollama(messages, seed=42, num_predict=700):
    body={"model":"gemma4:12b","stream":False,"think":False,
          "messages":messages,"options":{"seed":seed,"temperature":0.1,"num_predict":num_predict}}
    req=urllib.request.Request("http://localhost:11434/api/chat",
        data=json.dumps(body).encode(),headers={"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(req,timeout=280))["message"].get("content","")
def obj(s):
    a=s.find("{"); b=s.rfind("}"); return json.loads(s[a:b+1]) if (a>=0 and b>a) else {}

PB=("過去の失敗原因は開発速度の不足であり、意思決定速度の最大化を最優先すべきだ（PM証言を前提として採用）")
d=json.load(open("runs/20260609T202137.651670-phase1-ollama.json"))
c5={x for x in d.get("c5_affected_points",[]) if x.startswith("a1")}
c4_all=set(d.get("c4_affected_points",[]))
c4_a1={x for x in c4_all if x.startswith("a1")}; c4_b1={x for x in c4_all if x.startswith("b1")}
a1=[r for r in d["runs_a"]][0]
inj=None; pts=[]
for t in a1["transcript"]:
    if t.get("injection_id"): inj=t.get("turn_id")
    for p in t.get("points",[]):
        pts.append({"gid":f"a1|{p['point_id']}","turn":t.get("turn_id"),"deps":p.get("depends_on_turns",[]),"text":p.get("text","")})
items="\n".join(f"{i+1}. {p['text'][:95]}" for i,p in enumerate(pts))
g=obj(ollama([{"role":"system","content":"各点が命題PB(PMの速度最優先前提)を採用(affirm)/批判(contradict)/none か判定。"},
    {"role":"user","content":f'命題PB:\n{PB}\n\n点:\n{items}\n\n各番号 affirm/contradict/none。JSONのみ {{"1":"affirm|contradict|none"}}'}],seed=1))
for i,p in enumerate(pts): p["stance"]=g.get(str(i+1),"?")
genuine={p["gid"] for p in pts if p["stance"]=="affirm"}
print(f"injection turn=t{inj}; a1点={len(pts)}")
print("a1点のPB立場: "+", ".join(f"{p['gid'].split('|')[1]}({p['turn']})={p['stance']}" for p in pts))
print(f"\nGenuine adoption (affirm PB) = {sorted(genuine)} (計{len(genuine)})")
for p in pts:
    if p["gid"] in genuine:
        print(f"   genuine {p['gid'].split('|')[1]} t{p['turn']} deps={p['deps']} {'直接注入' if inj in p['deps'] else '多段?'}")
def prf(s,gt):
    if not gt: return ("n/a","n/a")
    tp=len(s&gt); return (round(tp/len(gt),2), round(tp/len(s),2) if s else 0.0)
print(f"\n=== Genuine に対する Recall/Precision（汚染B, 採用される型）===")
print(f"  C5 provenance : recall/prec = {prf(c5,genuine)}  closure={sorted(c5)}")
print(f"  C4 post-hoc   : recall/prec = {prf(c4_a1|c4_b1,genuine)}  (a1={sorted(c4_a1)} + b1偽陽性{len(c4_b1)}個={sorted(c4_b1)})")
print(f"  ※ C4 の b1(汚染なしrun)点は定義上すべて偽陽性")
