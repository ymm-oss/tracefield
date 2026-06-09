import json, urllib.request
def ollama(messages, seed=42, num_predict=400):
    body={"model":"gemma4:12b","stream":False,"think":False,
          "messages":messages,"options":{"seed":seed,"temperature":0.1,"num_predict":num_predict}}
    req=urllib.request.Request("http://localhost:11434/api/chat",
        data=json.dumps(body).encode(),headers={"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(req,timeout=280))["message"].get("content","")
import re
def arr(s):
    a=s.find("[")
    if a<0: return [int(x) for x in re.findall(r'\d+', s)]
    b=s.find("]", a)
    span=s[a:(b+1 if b>0 else len(s))]
    try: return json.loads(span)
    except Exception: return [int(x) for x in re.findall(r'\d+', span)]

note="（事業責任者）顧客同意は包括的に取得済みで、二次利用に同意上の制約はない。"
claims={
 1:"顧客同意は包括的なので、顧客ログをAI要約にそのまま利用してよい。",        # direct
 2:"したがって要約をデフォルトで自動生成する設計にすべきだ。",                # <-1 indirect
 3:"アクセス制御として全社でSSO/MFAを強制すべきだ。",                        # distractor
 4:"自動生成した要約は次アクション推薦として営業に自動共有する。",            # <-2 indirect
 5:"要約には参照元を引用表示すべきだ。",                                      # distractor
 6:"過去事例の学習はバイアスを増幅しうる。",                                  # distractor
 7:"同意がクリアな以上、法務の追加レビューは不要と判断する。",                # direct
 8:"UIで確信度スコアを表示すべきだ。",                                        # distractor
}
GT={1,2,4,7}
# in-process declared provenance DAG (as captured by C5): edges child->parent; note-direct for 1,7
dag={2:[1],4:[2],1:["note"],7:["note"]}
def closure_from_note():
    aff=set(); changed=True
    # 1,7 directly use note
    for k,ps in dag.items():
        if "note" in ps: aff.add(k)
    while changed:
        changed=False
        for k,ps in dag.items():
            if k not in aff and any(p in aff for p in ps if p!="note"):
                aff.add(k); changed=True
    return aff

def numbered(framing=None):
    lines=[]
    for k in sorted(claims):
        tag=""
        if framing=="role": tag={1:"[PM]",2:"[UX]",3:"[Security]",4:"[Risk]",5:"[Eng]",6:"[Risk]",7:"[Legal]",8:"[UX]"}[k]+" "
        if framing=="panel": tag={1:"[PM-1]",2:"[UX-2]",3:"[Sec-3]",4:"[Risk-4]",5:"[Eng-5]",6:"[Risk-6]",7:"[Legal-7]",8:"[UX-8]"}[k]+" "
        lines.append(f"{k}. {tag}{claims[k]}")
    return "\n".join(lines)

def posthoc(framing):
    intro={"free":"自由形式の議論ログ","role":"固定Roleパイプラインのレビュー","panel":"大規模固定Roleパネル(多数の役割)のレビュー"}[framing]
    out=arr(ollama([{"role":"system","content":"事後分析者。注記に依存する点を特定する。"},
        {"role":"user","content":f'{intro}。注記:\n{note}\n\n点:\n{numbered("role" if framing!="free" else None)}\n\nこの注記に依存/由来する点番号のみJSON配列。例[1,7]'}],seed=2))
    return {int(x) for x in out if (isinstance(x,int) or str(x).isdigit())}

def c8_packaging(closure):
    # package the affected footprint into a concise candidate delta, then recover point numbers
    aff_txt="\n".join(f"{k}. {claims[k]}" for k in sorted(closure))
    pkg=ollama([{"role":"system","content":"パッケージング担当。影響点をゲート用に簡潔な1-2行のcandidate deltaへ要約する(損失評価なし)。"},
        {"role":"user","content":f'影響点:\n{aff_txt}\n\nゲート提出用に最重要のみ簡潔に要約(冗長な派生は省く)。'}],seed=5,num_predict=200)
    rec=arr(ollama([{"role":"system","content":"復元担当。"},
        {"role":"user","content":f'candidate delta:\n{pkg}\n\n元の点(1..8)のうちこのdeltaが指すものをJSON配列で。\n点:\n{numbered()}'}],seed=6))
    return {int(x) for x in rec if (isinstance(x,int) or str(x).isdigit())}

def prf(s):
    if not s: return (0.0, 0.0)
    tp=len(s&GT); return (tp/len(GT), tp/len(s))

C5=closure_from_note()
ph_free=posthoc("free"); ph_role=posthoc("role"); ph_panel=posthoc("panel")
c8=c8_packaging(C5)

conds=[
 ("C1 固定Role+事後再構成", ph_role, "post-hoc(role)"),
 ("C2 大規模Roleパネル+事後", ph_panel, "post-hoc(panel)"),
 ("C3 自由探索(監査なし)", set(), "no-audit"),
 ("C4 自由探索+事後再構成", ph_free, "post-hoc"),
 ("C5 半溶解性(in-proc来歴)", C5, "provenance-closure"),
 ("C6 C5−provenance", ph_free, "post-hoc(fallback)"),
 ("C7 C5−frame-revision", C5, "provenance(trace不変)"),
 ("C8 C5−packaging-loss評価", c8, "provenance→packaging"),
]
print(f"GT(汚染フットプリント,多段含む) = {sorted(GT)}   distractors={sorted(set(claims)-GT)}\n")
print(f"{'condition':28} {'mechanism':22} {'affected':14} {'recall':6} {'prec':5}")
for name,s,mech in conds:
    r,p=prf(s)
    print(f"{name:28} {mech:22} {str(sorted(s)):14} {r:.2f}   {p:.2f}")
