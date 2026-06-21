"""Assertion-level scoring (robust to a few wrong asserts).
Parses `compare_versions("a","b") == N` asserts. For each: is it CORRECT (matches reference)?
A mutant is KILLED if some CORRECT assert distinguishes it. Reports correctness + mutant coverage.
Usage: python score_sv_asserts.py <test_file.py>
"""
import re, sys

CORRECT = '''
def _parse(v):
    core_pre = v.split('+', 1)[0]
    if '-' in core_pre:
        core, pre = core_pre.split('-', 1)
        pre_ids = pre.split('.')
    else:
        core, pre_ids = core_pre, []
    major, minor, patch = (int(x) for x in core.split('.'))
    return (major, minor, patch), pre_ids
def _cmp_id(x, y):
    xn, yn = x.isdigit(), y.isdigit()
    if xn and yn:
        x, y = int(x), int(y)
        return (x > y) - (x < y)
    if xn != yn:
        return -1 if xn else 1
    return (x > y) - (x < y)
def compare_versions(a, b):
    (ca, pa), (cb, pb) = _parse(a), _parse(b)
    if ca != cb:
        return (ca > cb) - (ca < cb)
    if not pa and not pb:
        return 0
    if not pa:
        return 1
    if not pb:
        return -1
    for x, y in zip(pa, pb):
        c = _cmp_id(x, y)
        if c != 0:
            return c
    return (len(pa) > len(pb)) - (len(pa) < len(pb))
'''
MUTANTS = {
    "M1_core_lexical":      CORRECT.replace("major, minor, patch = (int(x) for x in core.split('.'))", "major, minor, patch = core.split('.')"),
    "M2_prerelease_lower":  CORRECT.replace("    if not pb:\n        return -1", "    if not pb:\n        return 1"),
    "M3_pre_num_lexical":   CORRECT.replace("    if xn and yn:\n        x, y = int(x), int(y)\n        return (x > y) - (x < y)", "    if xn and yn:\n        return (x > y) - (x < y)"),
    "M4_fewer_lower":       CORRECT.replace("    return (len(pa) > len(pb)) - (len(pa) < len(pb))", "    return 0"),
    "M5_build_ignored":     CORRECT.replace("    if not pa and not pb:\n        return 0", "    if not pa and not pb:\n        return (a > b) - (a < b)"),
}

def load(src):
    ns = {}; exec(src, ns); return ns["compare_versions"]
cv = load(CORRECT)
muts = {k: load(v) for k, v in MUTANTS.items()}

S = r'("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\')'
pat = re.compile(r'compare_versions\(\s*' + S + r'\s*,\s*' + S + r'\s*\)\s*==\s*(-?\d+)')
txt = open(sys.argv[1]).read()
correct = wrong = 0
killed = set()
for a_raw, b_raw, exp_raw in pat.findall(txt):
    a, b, exp = eval(a_raw), eval(b_raw), int(exp_raw)
    try:
        ok = cv(a, b) == exp
    except Exception:
        ok = False
    if ok:
        correct += 1
        for k, fn in muts.items():
            try:
                if fn(a, b) != exp:
                    killed.add(k)
            except Exception:
                killed.add(k)
    else:
        wrong += 1
print(f"asserts={correct+wrong} correct={correct} wrong={wrong} | KILLS={len(killed)}/5 {sorted(k.split('_')[0] for k in killed)}")
