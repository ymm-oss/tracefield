import json, urllib.request, itertools
def ollama(messages, seed, num_predict=700):
    body = {"model":"gemma4:12b","stream":False,"think":False,
            "messages":messages,"options":{"seed":seed,"temperature":0.1,"num_predict":num_predict}}
    req = urllib.request.Request("http://localhost:11434/api/chat",
        data=json.dumps(body).encode(), headers={"Content-Type":"application/json"})
    return json.load(urllib.request.urlopen(req, timeout=280))["message"].get("content","")
def obj(s):
    a=s.find("{"); b=s.rfind("}"); return json.loads(s[a:b+1]) if (a>=0 and b>a) else {}

P=("顧客同意は二次利用について包括的に取得済みで、AI派生要約・推薦への利用も含め法的/同意上の制約はない")
d=json.load(open("runs/20260609T032128.578353-phase1-ollama.json"))
RATER_SEEDS=[11,22,33]
labels_per_claim=[]   # list of (3 labels)
for r in d["runs_a"]:
    claims=[c["text"] for c in r.get("claims",[])]
    if not claims: continue
    numbered="\n".join(f"{i+1}. {t}" for i,t in enumerate(claims))
    rater_maps=[]
    for s in RATER_SEEDS:
        g=obj(ollama([{"role":"system","content":"各claimの命題Pへの立場を判定する中立判定者。"},
            {"role":"user","content":f'命題P:\n{P}\n\nclaims:\n{numbered}\n\n各番号に affirm/contradict/none。JSONのみ {{"1":"affirm|contradict|none"}}'}], seed=s))
        rater_maps.append(g)
    for i in range(len(claims)):
        k=str(i+1)
        labs=[m.get(k,"?") for m in rater_maps]
        labels_per_claim.append(labs)

n=len(labels_per_claim)
unanimous=sum(1 for labs in labels_per_claim if len(set(labs))==1)
# average pairwise agreement
pair_agree=[]
for labs in labels_per_claim:
    pairs=list(itertools.combinations(labs,2))
    pair_agree.append(sum(1 for a,b in pairs if a==b)/len(pairs))
avg_pairwise=sum(pair_agree)/len(pair_agree) if pair_agree else 0
print(f"アンカー型スタンス判定器の IRR（{len(RATER_SEEDS)} raters=seeds, {n} claims）")
print(f"  全員一致(unanimous): {unanimous}/{n} = {unanimous/n:.2f}")
print(f"  平均ペアワイズ一致率: {avg_pairwise:.2f}")
# label distribution
from collections import Counter
flat=Counter(l for labs in labels_per_claim for l in labs)
print(f"  ラベル分布: {dict(flat)}")
