"""Extract+assemble the generated pytest from a run's stage (mechanical concat of all stage entries).
Usage: python extract.py <run.jsonl> <stage> <out.py>"""
import json, re, sys

run, stage, out = sys.argv[1], sys.argv[2], sys.argv[3]
fence = "`" * 3
parts = []
for l in open(run):
    e = json.loads(l)
    if e.get("meta", {}).get("stage") == stage:
        t = e.get("text", "")
        mm = re.search(fence + r"python\s*(.*?)" + fence, t, re.S) or re.search(fence + r"\s*(.*?)" + fence, t, re.S)
        code = mm.group(1) if mm else t
        if "merge_intervals" in code or "def test" in code or "import" in code:
            parts.append(code.strip())

body = "\n\n".join(parts)
# no hardcoded import injection (was wrong-function bug); only ensure pytest import if code uses it
header = ""
if "import pytest" not in body and ("pytest." in body or "@pytest" in body):
    header = "import pytest\n"
open(out, "w").write(header + body + "\n")
n = (header + body).count("def test_") + (header + body).count("parametrize")
print(f"stage={stage}: {len(parts)} fragments -> {len(header+body)} chars, ~{n} test groups")
