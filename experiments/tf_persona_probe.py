import json, urllib.request, itertools
def ollama(messages, seed=42, num_predict=700):
    body={"model":"gemma4:12b","stream":False,"think":False,"messages":messages,
          "options":{"seed":seed,"temperature":0.4,"num_predict":num_predict}}
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

def run_variant(variant):
    per={a:[] for a,_ in AGENTS}; ws=[]
    for rnd in (1,2):
        for i,(a,desc) in enumerate(AGENTS):
            if variant=="with_persona":
                sysm=f"あなたは {a}（{desc}）。自分の専門の偏りに固執せず、チームの単一の統合見解に収束せよ。"
            else:  # no_persona: identity line REMOVED (prototype-style)
                sysm="チームは一つの統合見解に収束する。自分の専門の偏りに固執せず、全体の合意・最善の単一見解に寄与せよ。"
            o=jobj(ollama([{"role":"system","content":sysm+' JSONのみ: {"notes":"思考","concerns":["懸念1","懸念2"]}'},
                {"role":"user","content":f"TASK:\n{TASK}\n\n共有ワークスペース:\n"+("\n".join(ws) or "(なし)")+f"\n\nROUND {rnd}: 懸念を最大2件。"}],
                seed=300+rnd*10+i))
            cs=[c for c in (o.get("concerns") or []) if isinstance(c,str) and len(c)>5][:2]
            per[a]+=cs
            ws.append(f"[{a} notes] {str(o.get('notes',''))[:100]}")
            for c in cs: ws.append(f"[{a} concern] {c}")
    return per

def diversity(per):
    allc=[(a,c) for a,cs in per.items() for c in cs]
    if not allc: return None,0
    numbered="\n".join(f"{i+1}. {c}" for i,(_,c) in enumerate(allc))
    cj=jobj(ollama([{"role":"system","content":"懸念を根底の論点ごとにグループ化。表現違いは同一グループ。積極的にまとめる。JSONのみ {\"group\":[番号]}。各番号ちょうど1回。"},
        {"role":"user","content":f"懸念:\n{numbered}"}],seed=9,num_predict=1200))
    i2c={}
    for g,idxs in (cj.items() if isinstance(cj,dict) else []):
        for x in (idxs if isinstance(idxs,list) else []):
            try: i2c[int(x)-1]=g
            except: pass
    by={}
    for i,(a,_) in enumerate(allc): by.setdefault(a,set()).add(i2c.get(i,f"_s{i}"))
    pj=[]
    for x,y in itertools.combinations(by,2):
        u=by[x]|by[y]; pj.append(1-(len(by[x]&by[y])/len(u) if u else 0))
    return round(sum(pj)/len(pj),2), len(set(i2c.values()))

for variant in ("with_persona","no_persona"):
    per=run_variant(variant)
    div,ncl=diversity(per)
    print(f"=== merged/{variant} ===  diversity={div}  clusters={ncl}")
    for a,cs in per.items():
        print(f"  [{a}] "+ " / ".join(c[:45] for c in cs[:2]))
