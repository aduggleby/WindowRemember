#!/usr/bin/env python3
"""Offline heuristic audit of every published-branch/tag Git blob and commit metadata.

Prints locations and rule names, never matched secret values. This complements
manual review; no automated scanner can guarantee the absence of all secrets.
"""
import re
import subprocess
import sys

rules = {
    "private-key": rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----",
    "github-token": rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})",
    "aws-access-key": rb"(?:AKIA|ASIA)[A-Z0-9]{16}",
    "api-secret": rb"\bsk-(?:proj-)?[A-Za-z0-9_-]{32,}",
    "slack-token": rb"xox[baprs]-[A-Za-z0-9-]{20,}",
    "local-home-path": rb"/(?:Users|home)/[A-Za-z0-9][A-Za-z0-9_.-]*/",
    "private-hostname": rb"\b[A-Za-z0-9-]+\.ohana\b",
    "private-network-address": rb"\b(?:192\.168\.[0-9]{1,3}\.[0-9]{1,3}|10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3})\b",
}
patterns = {name: re.compile(pattern) for name, pattern in rules.items()}
objects = subprocess.check_output(["git", "rev-list", "--objects", "--branches", "--tags", "--remotes"]).splitlines()
locations = {}
for line in objects:
    parts = line.split(b" ", 1)
    locations[parts[0]] = parts[1].decode(errors="replace") if len(parts) > 1 else "commit/tree"
payload = b"\n".join(locations) + b"\n"
result = subprocess.check_output(["git", "cat-file", "--batch"], input=payload)
position = 0
findings = []
blob_count = 0
for _ in locations:
    end = result.index(b"\n", position)
    sha, kind, length = result[position:end].split()
    start = end + 1
    data = result[start:start + int(length)]
    position = start + int(length) + 1
    if kind not in (b"blob", b"commit", b"tag"):
        continue
    if kind == b"blob":
        blob_count += 1
    for name, pattern in patterns.items():
        if pattern.search(data):
            findings.append((sha.decode()[:12], locations[sha], name))
for sha, path, rule in findings:
    print(f"REVIEW {sha} {path}: {rule}")
print(f"Audited {blob_count} reachable file versions and Git metadata; {len(findings)} findings.")
sys.exit(bool(findings))
