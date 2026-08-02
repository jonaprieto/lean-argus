#!/usr/bin/env python3
"""Check Lean files for line length, trailing whitespace, and tabs."""

import subprocess
import sys

MAX = 100
files = subprocess.check_output(["git", "ls-files", "*.lean"], text=True).split()
violations = []
for f in files:
    for i, line in enumerate(open(f, encoding="utf-8"), 1):
        line = line.rstrip("\n")
        if len(line) > MAX:
            violations.append(f"{f}:{i}: line is {len(line)} cols (>{MAX})")
        if line != line.rstrip():
            violations.append(f"{f}:{i}: trailing whitespace")
        if "\t" in line:
            violations.append(f"{f}:{i}: tab character")

for violation in violations:
    print(violation)
print(f"{'FAIL' if violations else 'OK'}: {len(files)} Lean files, {len(violations)} violations")
sys.exit(1 if violations else 0)
