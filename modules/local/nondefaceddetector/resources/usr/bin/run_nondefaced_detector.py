#!/usr/bin/env python3

import argparse
import csv
import json
import os
import re
import subprocess
import sys


def parse_stdout(text: str):
    score = None
    pred_class = None

    m = re.search(r"Final layer output:\s*\[?([0-9eE+\-\.]+)\]?", text)
    if m:
        score = float(m.group(1))

    m = re.search(r"Predicted Class:\s*([A-Z]+)", text)
    if m:
        pred_class = m.group(1)

    return score, pred_class


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--model-path", required=True)
    parser.add_argument("--method", required=True)
    parser.add_argument("--project", default="")
    parser.add_argument("--subject", default="")
    parser.add_argument("--session", default="")
    parser.add_argument("--threshold", type=float, default=0.5)
    parser.add_argument("--preprocess-path", default="tmp_preproc")
    parser.add_argument("--out-json", required=True)
    parser.add_argument("--out-tsv", required=True)
    parser.add_argument("--out-log", required=True)
    args = parser.parse_args()

    cmd = [
        "nondefaced-detector",
        "predict",
        "--model-path", args.model_path,
        "--classifier-threshold", str(args.threshold),
        "--preprocess-path", args.preprocess_path,
        args.input,
    ]

    proc = subprocess.run(cmd, capture_output=True, text=True)

    with open(args.out_log, "w") as f:
        f.write("CMD: " + " ".join(cmd) + "\n\n")
        f.write("STDOUT\n======\n")
        f.write(proc.stdout or "")
        f.write("\n\nSTDERR\n======\n")
        f.write(proc.stderr or "")

    if proc.returncode != 0:
        raise RuntimeError(f"nondefaced-detector failed with exit code {proc.returncode}")

    score, pred_class = parse_stdout(proc.stdout)

    row = {
        "project": args.project,
        "subject": args.subject,
        "session": args.session,
        "method": args.method,
        "input_file": os.path.basename(args.input),
        "tool": "nondefaced-detector",
        "classifier_threshold": args.threshold,
        "score": score,
        "predicted_class": pred_class,
    }

    with open(args.out_json, "w") as f:
        json.dump(row, f, indent=2)

    with open(args.out_tsv, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(row.keys()), delimiter="\t")
        writer.writeheader()
        writer.writerow(row)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        raise
