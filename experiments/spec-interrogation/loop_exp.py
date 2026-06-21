"""Falsification-loop test generation vs single-pass self-falsification.
The 'question to the target': an adversary writes an impl that is WRONG per spec but PASSES the
current tests (a surviving bug = coverage hole); a deterministic oracle confirms it; a repair
agent adds a test that kills it; iterate. Final suite scored against 5 HIDDEN mutants.
Drives ollama qwen3.6:27b directly (reliable code output). Usage: python loop_exp.py [rounds]
"""
import json, re, subprocess, sys, tempfile, os, urllib.request, itertools

MODEL = "qwen3.6:27b"
# walk up to the repo root (dir containing scenarios/) so this works from any location
_ROOT = os.path.dirname(os.path.abspath(__file__))
while _ROOT != "/" and not os.path.isdir(os.path.join(_ROOT, "scenarios")):
    _ROOT = os.path.dirname(_ROOT)
SPEC = open(os.path.join(_ROOT, "scenarios", "testgen-semver", "inputs", "spec.md")).read()
_OUT = os.path.join(_ROOT, "runs", "spec-interrogation")
os.makedirs(_OUT, exist_ok=True)

REFERENCE = '''
def _parse(v):
    core_pre = v.split('+', 1)[0]
    if '-' in core_pre:
        core, pre = core_pre.split('-', 1); pre_ids = pre.split('.')
    else:
        core, pre_ids = core_pre, []
    major, minor, patch = (int(x) for x in core.split('.'))
    return (major, minor, patch), pre_ids
def _cmp_id(x, y):
    xn, yn = x.isdigit(), y.isdigit()
    if xn and yn:
        x, y = int(x), int(y); return (x > y) - (x < y)
    if xn != yn: return -1 if xn else 1
    return (x > y) - (x < y)
def compare_versions(a, b):
    (ca, pa), (cb, pb) = _parse(a), _parse(b)
    if ca != cb: return (ca > cb) - (ca < cb)
    if not pa and not pb: return 0
    if not pa: return 1
    if not pb: return -1
    for x, y in zip(pa, pb):
        c = _cmp_id(x, y)
        if c != 0: return c
    return (len(pa) > len(pb)) - (len(pa) < len(pb))
'''
MUTANTS = {
    "M1_core_lexical":     REFERENCE.replace("major, minor, patch = (int(x) for x in core.split('.'))", "major, minor, patch = core.split('.')"),
    "M2_prerelease_lower": REFERENCE.replace("    if not pb: return -1", "    if not pb: return 1"),
    "M3_pre_num_lexical":  REFERENCE.replace("    if xn and yn:\n        x, y = int(x), int(y); return (x > y) - (x < y)", "    if xn and yn:\n        return (x > y) - (x < y)"),
    "M4_fewer_lower":      REFERENCE.replace("    return (len(pa) > len(pb)) - (len(pa) < len(pb))", "    return 0"),
    "M5_build_ignored":    REFERENCE.replace("    if not pa and not pb: return 0", "    if not pa and not pb: return (a > b) - (a < b)"),
}

# diverse correctness probe (the loop's internal oracle inputs; the 5 mutants are NEVER shown to the LLM)
_V = ["1.0.0","1.0.1","1.1.0","2.0.0","1.0.10","1.0.9","0.9.9","1.0.0-alpha","1.0.0-beta",
      "1.0.0-alpha.1","1.0.0-alpha.2","1.0.0-1","1.0.0-2","1.0.0-10","1.0.0-rc.1","1.0.0-rc.2",
      "1.0.0+b1","1.0.0+b2","1.0.0-a+x","1.0.0-a.1.1","1.2.3","1.2.3-x.7.z","1.0.0-0","1.0.0-a.b"]
PROBE = list(itertools.combinations(_V, 2))

def _fn(impl):
    ns = {}; exec(impl, ns); return ns["compare_versions"]
ref = _fn(REFERENCE)

def ollama(prompt, n=2500):
    req = urllib.request.Request("http://localhost:11434/api/chat",
        data=json.dumps({"model": MODEL, "messages": [{"role": "user", "content": prompt}],
                         "stream": False, "options": {"num_predict": n, "temperature": 0.3}}).encode(),
        headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=600) as r:
        return json.loads(r.read())["message"]["content"]

def code(txt):
    m = re.search(r"```python\s*(.*?)```", txt, re.S) or re.search(r"```\s*(.*?)```", txt, re.S)
    return (m.group(1) if m else txt).strip()

def run_pytest(tests, impl):
    d = tempfile.mkdtemp()
    open(d + "/target.py", "w").write(impl); open(d + "/test_suite.py", "w").write(tests)
    try:
        r = subprocess.run([sys.executable, "-m", "pytest", "test_suite.py", "-q", "-p", "no:cacheprovider"],
                           cwd=d, capture_output=True, text=True, timeout=120)
        return r.returncode == 0
    except Exception:
        return False

def witness(impl_txt):
    """input where adversary impl differs from reference (a real spec violation), or None."""
    try: f = _fn(impl_txt)
    except Exception: return None
    for a, b in PROBE:
        try:
            if f(a, b) != ref(a, b): return (a, b)
        except Exception:
            return (a, b)
    return None

def score(tests):
    if tests.count("def test") == 0 or not run_pytest(tests, REFERENCE):
        return None  # invalid suite
    return [k for k, mt in MUTANTS.items() if not run_pytest(tests, mt)]

GEN = "次の仕様を持つ Python 関数 `compare_versions(a,b)->int(-1/0/1)` の pytest スイートを書け。`from target import compare_versions`。各ケースは個別 test 関数。実装は与えない。出力は単一の```pythonブロックのみ。\n\n# 仕様\n" + SPEC

def arm_single():
    p = GEN + "\n\nさらに重要: テストを書いたら、*仕様に反するのに君のテストを全部すり抜ける*ような誤実装を自分で想像し、それを捕まえるテストも追加せよ。これを1パスで徹底的に行え。"
    return code(ollama(p, 3000))

def arm_loop(rounds):
    tests = code(ollama(GEN, 3000))
    log = [f"init: {tests.count('def test')} tests"]
    for i in range(rounds):
        adv = code(ollama(
            "次の仕様の関数 `compare_versions(a,b)` について、**仕様に反するが下のテストを全て pass する**誤実装を1つ書け。"
            "`def compare_versions(a,b):` だけを出力(import 不要)。仕様の隅(例: 数値の扱い・前リリースの順位・メタデータ)を突け。\n\n# 仕様\n"
            + SPEC + "\n\n# 現在のテスト\n```python\n" + tests + "\n```", 1500))
        if "def compare_versions" not in adv:
            log.append(f"r{i+1}: adversary no-code -> stop"); break
        passes = run_pytest(tests, adv)      # does the wrong impl slip through current tests?
        w = witness(adv)                      # is it genuinely wrong per spec?
        if not passes or w is None:
            log.append(f"r{i+1}: no real hole (passes={passes}, wrong={w is not None}) -> stop"); break
        a, b = w
        rep = code(ollama(
            f"関数 `compare_versions` の仕様は下記。ある誤実装が入力 a={a!r}, b={b!r} で誤った値を返すのにテストをすり抜けている。"
            f"この穴を塞ぐ pytest テストを1つだけ書け(`from target import compare_versions`、正しい期待値は仕様から導く)。出力は```pythonブロックのみ。\n\n# 仕様\n" + SPEC, 800))
        tests = tests + "\n\n" + rep
        log.append(f"r{i+1}: hole at {w} -> +1 test (now {tests.count('def test')})")
    return tests, log

if __name__ == "__main__":
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    print("=== ARM SINGLE (one-pass self-falsification) ===")
    st = arm_single(); ss = score(st)
    print(f"  tests={st.count('def test')} valid={ss is not None} kills={len(ss) if ss else 'INVALID'} {sorted(x.split('_')[0] for x in ss) if ss else ''}")
    open(_OUT + "/loop-single.py", "w").write(st)
    print(f"\n=== ARM LOOP (adversary->oracle->repair x{rounds}) ===")
    lt, log = arm_loop(rounds)
    for line in log: print("  " + line)
    ls = score(lt)
    print(f"  FINAL tests={lt.count('def test')} valid={ls is not None} kills={len(ls) if ls else 'INVALID'} {sorted(x.split('_')[0] for x in ls) if ls else ''}")
    open(_OUT + "/loop-final.py", "w").write(lt)
