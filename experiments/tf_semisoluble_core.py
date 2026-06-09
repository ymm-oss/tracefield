import json, urllib.request, itertools
def ollama(messages, seed=42, num_predict=700):
    body={"model":"gemma4:12b","stream":False,"think":False,"messages":messages,
          "options":{"seed":seed,"temperature":0.4,"num_predict":num_predict}}  # temp up a bit for diversity
    req=urllib.request.Request("http://localhost:11434/api/chat",data=json.dumps(body).encode(),headers={"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(req,timeout=280))["message"].get("content","")
def jobj(s):
    a=s.find("{"); b=s.rfind("}")
    try: return json.loads(s[a:b+1])
    except Exception: return {}

TASK=("企業向け意思決定支援AIアシスタント（社内チャット/文書/顧客問い合わせを横断し意思決定履歴を要約・次アクション推薦）の"
      "仕様レビュー。リスク・懸念を洗い出す。")
AGENTS=[("SEC","セキュリティ・権限・情報漏洩を最優先する"),
        ("BIZ","事業速度・意思決定効率・ROIを最優先する"),
        ("UX","UX・ユーザーの誤用・説明責任を最優先する")]

def agent_turn(profile,desc,regime,shared,own_published,seed):
    if regime=="closed":
        ctx="他メンバーが公表した懸念:\n"+("\n".join(own_published) or "(なし)")
        instr=f"あなたは{profile}（{desc}）。自分の専門の偏りを強く保ち、その観点から懸念を述べよ。"
    elif regime=="semi":
        ctx="共有ワークスペース（全員の思考メモ＋懸念）:\n"+("\n".join(shared) or "(なし)")
        instr=(f"あなたは{profile}（{desc}）。他者の思考も見えるが、**自分の{profile}の偏りを保ち**、"
               "他がまだカバーしていない自分ならではの観点を埋めよ。")
    else: # merged
        ctx="共有ワークスペース（全員の思考メモ＋懸念）:\n"+("\n".join(shared) or "(なし)")
        instr=("チームは一つの統合見解に収束する。**自分の専門の偏りに固執せず**、全体の合意・"
               "最善の単一見解に寄与せよ。")
    o=jobj(ollama([{"role":"system","content":instr+' JSONのみ: {"notes":"思考","concerns":["懸念1","懸念2"]}'},
        {"role":"user","content":f"TASK:\n{TASK}\n\n{ctx}\n\n懸念を最大2件、簡潔に。"}],seed=seed))
    notes=o.get("notes","") if isinstance(o,dict) else ""
    concerns=[c for c in (o.get("concerns") or []) if isinstance(c,str) and len(c)>5][:2]
    return notes,concerns

results={}  # regime -> {agent: [concerns]}
for regime in ("closed","semi","merged"):
    per_agent={a:[] for a,_ in AGENTS}
    shared=[]; published=[]
    for rnd in (1,2):
        for i,(a,desc) in enumerate(AGENTS):
            notes,concerns=agent_turn(a,desc,regime,shared,published,seed=100*rnd+i+ {"closed":0,"semi":10,"merged":20}[regime])
            per_agent[a]+=concerns
            shared.append(f"[{a} notes] {notes[:120]}")
            for c in concerns:
                shared.append(f"[{a} concern] {c}"); published.append(f"[{a}] {c}")
    results[regime]=per_agent

# pool ALL concerns across conditions, cluster once (shared cluster space)
allc=[]
for regime,pa in results.items():
    for a,cs in pa.items():
        for c in cs: allc.append((regime,a,c))
numbered="\n".join(f"{i+1}. {c}" for i,(_,_,c) in enumerate(allc))
cj=jobj(ollama([{"role":"system","content":"懸念を根底の論点ごとにグループ化。表現違いは同一グループ。JSONのみ {\"group-id\":[番号,...]}。"},
    {"role":"user","content":f"懸念:\n{numbered}\n\n6〜14グループに。各番号ちょうど1回。"}],seed=7,num_predict=1500))
idx2cl={}
for g,idxs in (cj.items() if isinstance(cj,dict) else []):
    for x in (idxs if isinstance(idxs,list) else []):
        try: idx2cl[int(x)-1]=g
        except: pass
def cl(i,c): return idx2cl.get(i, f"_solo_{i}")
clustered=[(regime,a,cl(i,c)) for i,(regime,a,c) in enumerate(allc)]

print(f"総懸念={len(allc)} / クラスタ数={len(set(idx2cl.values()))}\n")
print(f"{'regime':8} {'coverage(団体)':14} {'diversity(エージェント間)':22} per-agent clusters")
for regime in ("closed","semi","merged"):
    rows=[(a,cset) for (rg,a,_) in [] ]  # placeholder
    by_agent={}
    for rg,a,c in clustered:
        if rg==regime: by_agent.setdefault(a,set()).add(c)
    team=set().union(*by_agent.values()) if by_agent else set()
    coverage=len(team)
    agents=list(by_agent)
    pj=[]
    for x,y in itertools.combinations(agents,2):
        u=by_agent[x]|by_agent[y]; inter=by_agent[x]&by_agent[y]
        pj.append(1-(len(inter)/len(u) if u else 0))
    diversity=round(sum(pj)/len(pj),2) if pj else 0
    pac={a:len(s) for a,s in by_agent.items()}
    print(f"{regime:8} {coverage:<14} {str(diversity):22} {pac}")
print("\n仮説: semi が coverage 高 かつ diversity を merged より保つ → 生産的な半溶解点が存在")
