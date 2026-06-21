"""Mutation-testing ground truth for the HARDER target: semver `compare_versions(a,b) -> -1|0|1`.
Each mutant = a distinct SUBTLE semver precedence rule (the kind a single pass reliably misses).
Usage: python score_sv.py <generated_test_file.py>   (tests import `from target import compare_versions`)
"""
import subprocess, sys, tempfile, os

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
    "M1_core_lexical(1.0.10 vs 1.0.9)":        CORRECT.replace("major, minor, patch = (int(x) for x in core.split('.'))", "major, minor, patch = core.split('.')"),
    "M2_prerelease_not_lower(x-alpha vs x)":   CORRECT.replace("    if not pb:\n        return -1", "    if not pb:\n        return 1"),
    "M3_pre_numeric_lexical(-2 vs -10)":       CORRECT.replace("    if xn and yn:\n        x, y = int(x), int(y)\n        return (x > y) - (x < y)", "    if xn and yn:\n        return (x > y) - (x < y)"),
    "M4_fewer_not_lower(-a vs -a.1)":          CORRECT.replace("    return (len(pa) > len(pb)) - (len(pa) < len(pb))", "    return 0"),
    "M5_build_not_ignored(+1 vs +2)":          CORRECT.replace("    if not pa and not pb:\n        return 0", "    if not pa and not pb:\n        return (a > b) - (a < b)"),
}

def run(txt, impl):
    d = tempfile.mkdtemp()
    open(os.path.join(d, "target.py"), "w").write(impl)
    open(os.path.join(d, "test_suite.py"), "w").write(txt)
    try:
        r = subprocess.run([sys.executable, "-m", "pytest", "test_suite.py", "-q", "--no-header", "-p", "no:cacheprovider"],
                           cwd=d, capture_output=True, text=True, timeout=120)
        return r.returncode == 0, r.stdout
    except Exception as e:
        return False, str(e)

def main():
    txt = open(sys.argv[1]).read()
    if txt.count("def test") == 0:
        print("INVALID: no test functions (prose, not code). kills=N/A"); return
    valid, out = run(txt, CORRECT)
    if not valid:
        print(f"INVALID SUITE: fails on CORRECT impl -> kills meaningless. ntests={txt.count('def test')}")
        for line in out.splitlines():
            if "assert" in line or "Error" in line:
                print("   " + line.strip()[:120]); break
        return
    kills = 0
    for name, impl in MUTANTS.items():
        passed, _ = run(txt, impl)
        kills += (not passed)
        print(f"  {name:36s}: {'KILLED' if not passed else 'survived'}")
    print(f"KILL RATE: {kills}/{len(MUTANTS)}   (valid, ntests={txt.count('def test')})")

if __name__ == "__main__":
    main()
