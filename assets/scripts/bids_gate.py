#!/usr/bin/env python3
import argparse
import json
import re
import sys
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple

ISSUE_RE = re.compile(r"\[(WARNING|ERROR)\]\s+([A-Z0-9_]+)\b(.*)")

FILELINE_RE = re.compile(r"^\s*(/[^ \t]+)")

DEFAULT_FAIL_WARNINGS = {
    # defaults
}

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Gate BIDS Validator output (fail on policy).")
    p.add_argument("--log", required=True, help="Path to bids-validator stdout/stderr log")
    p.add_argument("--json", dest="json_out", default=None, help="Write JSON report to this path")
    p.add_argument("--policy", choices=["nfcore", "strict", "custom"], default="nfcore",
                   help="nfcore: fail on ERROR only; strict: fail on ERROR + common warnings; custom: use lists")
    p.add_argument("--fail-on-warning", default="", help="Comma-separated warning codes that should fail")
    p.add_argument("--ignore-warning", default="", help="Comma-separated warning codes to always ignore")
    p.add_argument("--no-fail-on-error", action="store_true", help="Do not fail on ERROR (not recommended)")
    return p.parse_args()

def split_codes(s: str) -> List[str]:
    if not s.strip():
        return []
    return [x.strip() for x in s.split(",") if x.strip()]

def parse_log(text: str) -> List[Dict[str, Any]]:
    issues: List[Dict[str, Any]] = []
    cur: Optional[Dict[str, Any]] = None

    def flush():
        nonlocal cur
        if cur:
            # normalize / dedupe file list
            cur["files"] = sorted(set(cur["files"]))
            cur["message"] = cur["message"].strip()
            issues.append(cur)
            cur = None

    for raw in text.splitlines():
        line = raw.rstrip("\n")

        m = ISSUE_RE.search(line)
        if m:
            flush()
            severity, code, rest = m.group(1), m.group(2), (m.group(3) or "").strip()
            cur = {
                "severity": severity,
                "code": code,
                "message": rest,
                "files": [],
                "raw": [line],
            }
            continue

        if cur is None:
            continue

        cur["raw"].append(line)

        # Collect file path references that begin with "/"
        s = line.strip()
        fm = FILELINE_RE.match(s)
        if fm:
            cur["files"].append(fm.group(1))
        else:
            # Accumulate message context (but keep it short-ish)
            if s and not s.startswith("Please visit") and not s.startswith("See Section"):
                # append additional explanatory lines
                cur["message"] += ("\n" + s)

    flush()
    return issues

def apply_policy(
    issues: List[Dict[str, Any]],
    fail_on_error: bool,
    fail_warnings: List[str],
    ignore_warnings: List[str],
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    ignore_set = set(ignore_warnings)
    fail_warn_set = set(fail_warnings)

    important: List[Dict[str, Any]] = []
    informational: List[Dict[str, Any]] = []

    for it in issues:
        sev = it["severity"]
        code = it["code"]

        if sev == "WARNING" and code in ignore_set:
            informational.append(it)
            continue

        if sev == "ERROR":
            (important if fail_on_error else informational).append(it)
            continue

        # WARNING
        if code in fail_warn_set:
            important.append(it)
        else:
            informational.append(it)

    return important, informational

def main() -> int:
    args = parse_args()
    log_path = Path(args.log)
    if not log_path.exists():
        print(f"[bids-gate] ERROR: log not found: {log_path}", file=sys.stderr)
        return 2

    text = log_path.read_text(errors="replace")
    issues = parse_log(text)

    # policy -> warning fail set
    if args.policy == "nfcore":
        fail_warnings = []
    elif args.policy == "strict":
        fail_warnings = sorted(DEFAULT_FAIL_WARNINGS)
    else:  # custom
        fail_warnings = []

    # apply CLI additions
    fail_warnings += split_codes(args.fail_on_warning)
    ignore_warnings = split_codes(args.ignore_warning)

    # dedupe
    fail_warnings = sorted(set(fail_warnings))
    ignore_warnings = sorted(set(ignore_warnings))

    important, informational = apply_policy(
        issues=issues,
        fail_on_error=(not args.no_fail_on_error),
        fail_warnings=fail_warnings,
        ignore_warnings=ignore_warnings,
    )

    # Build report
    report = {
        "log": str(log_path),
        "counts": {
            "total": len(issues),
            "important": len(important),
            "informational": len(informational),
            "errors": sum(1 for x in issues if x["severity"] == "ERROR"),
            "warnings": sum(1 for x in issues if x["severity"] == "WARNING"),
        },
        "policy": {
            "policy": args.policy,
            "fail_on_error": (not args.no_fail_on_error),
            "fail_warnings": fail_warnings,
            "ignore_warnings": ignore_warnings,
        },
        "important": important,
        "informational": informational,
    }

    # Human summary
    print(f"[bids-gate] total issues: {report['counts']['total']} "
          f"(errors={report['counts']['errors']}, warnings={report['counts']['warnings']})")
    print(f"[bids-gate] IMPORTANT issues: {report['counts']['important']}")
    if important:
        print("\n[bids-gate] Failing on:")
        for it in important:
            files = ", ".join(it["files"][:5]) + (" …" if len(it["files"]) > 5 else "")
            print(f"  - {it['severity']} {it['code']}" + (f" | {files}" if files else ""))
    else:
        print("[bids-gate] No failing issues found.")

    if args.json_out:
        Path(args.json_out).write_text(json.dumps(report, indent=2))

    return 1 if important else 0

if __name__ == "__main__":
    raise SystemExit(main())

