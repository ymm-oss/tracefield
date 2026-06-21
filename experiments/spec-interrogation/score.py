"""Mutation-testing ground truth for the test-generation experiment.
Given a generated pytest file, run it against the correct impl (must pass = suite valid)
and against 5 mutants (each = a distinct failure mode). A mutant is KILLED iff the suite fails on it.
kill-rate = how many real failure modes the suite actually discovered. Deterministic, no judge.
Usage: python score.py <generated_test_file.py>
"""
import subprocess, sys, tempfile, os

CORRECT = '''
def merge_intervals(intervals):
    if not intervals:
        return []
    s = sorted(intervals, key=lambda x: x[0])
    out = [list(s[0])]
    for a, b in s[1:]:
        if a <= out[-1][1]:
            out[-1][1] = max(out[-1][1], b)
        else:
            out.append([a, b])
    return out
'''

# each mutant injects ONE bug tied to one failure mode
MUTANTS = {
    "M1_adjacency(touching not merged)": CORRECT.replace("if a <= out[-1][1]:", "if a < out[-1][1]:"),
    "M2_no_sort(unsorted input)":        CORRECT.replace("s = sorted(intervals, key=lambda x: x[0])", "s = [list(x) for x in intervals]"),
    "M3_nested(inner end overwrites)":   CORRECT.replace("out[-1][1] = max(out[-1][1], b)", "out[-1][1] = b"),
    "M4_empty(no guard -> crash)":       CORRECT.replace("    if not intervals:\n        return []\n", ""),
    "M5_offbyone(over-merge gap=1)":     CORRECT.replace("if a <= out[-1][1]:", "if a <= out[-1][1] + 1:"),
}

def run(testfile_text, impl):
    d = tempfile.mkdtemp()
    open(os.path.join(d, "target.py"), "w").write(impl)
    open(os.path.join(d, "test_suite.py"), "w").write(testfile_text)
    try:
        r = subprocess.run([sys.executable, "-m", "pytest", "test_suite.py", "-q", "--no-header", "-p", "no:cacheprovider"],
                           cwd=d, capture_output=True, text=True, timeout=120)
        return r.returncode == 0, r.stdout
    except Exception as e:
        return False, str(e)

def main():
    txt = open(sys.argv[1]).read()
    ntests = txt.count("def test")
    if ntests == 0:
        print(f"INVALID: no test functions extracted (model emitted prose, not code). kills=N/A")
        return
    valid, out = run(txt, CORRECT)
    if not valid:
        print(f"INVALID SUITE: fails on CORRECT impl (spec misread or broken) -> kills meaningless. ntests={ntests}")
        # show the first failing assertion for diagnosis
        for line in out.splitlines():
            if "assert" in line or "Error" in line:
                print("   " + line.strip()[:120]); break
        return
    kills = 0
    for name, impl in MUTANTS.items():
        passed, _ = run(txt, impl)
        killed = not passed
        kills += killed
        print(f"  {name:38s}: {'KILLED' if killed else 'survived'}")
    print(f"KILL RATE: {kills}/{len(MUTANTS)}   (valid, ntests={ntests})")

if __name__ == "__main__":
    main()
