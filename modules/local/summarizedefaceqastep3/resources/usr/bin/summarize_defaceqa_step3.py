#!/usr/bin/env python3

import argparse
import csv
import json
import math
import statistics
import sys
from collections import defaultdict


NUMERIC_COLUMNS = [
    "pct_brain_removed",
    "pct_brain_altered",
    "pct_face_shell_removed",
    "pct_face_shell_altered",
    "pct_head_removed",
    "pct_head_altered",
    "brain_relative_to_head_pct",
    "rmse_brain",
    "rmse_head",
    "pearson_brain",
    "pearson_head",
    "ssim_center_mean",
    "ssim_sagittal_center",
    "ssim_coronal_center",
    "ssim_axial_center",
]


def to_float(x):
    if x is None:
        return None
    s = str(x).strip()
    if s == "" or s.lower() == "nan":
        return None
    try:
        v = float(s)
    except ValueError:
        return None
    if math.isnan(v):
        return None
    return v


def summarize(values):
    vals = [v for v in values if v is not None]
    if not vals:
        return {
            "n": 0,
            "mean": "",
            "median": "",
            "min": "",
            "max": "",
            "stddev": "",
        }
    return {
        "n": len(vals),
        "mean": statistics.fmean(vals),
        "median": statistics.median(vals),
        "min": min(vals),
        "max": max(vals),
        "stddev": statistics.stdev(vals) if len(vals) > 1 else 0.0,
    }


def main():
    parser = argparse.ArgumentParser(description="Summarize merged DefaceQA Step 3 TSV by method.")
    parser.add_argument("--input", required=True, help="Merged Step 3 TSV")
    parser.add_argument("--out-tsv", required=True, help="Method summary TSV")
    parser.add_argument("--out-json", required=True, help="Method summary JSON")
    args = parser.parse_args()

    rows_by_method = defaultdict(list)

    with open(args.input, "r", newline="") as f:
        reader = csv.DictReader(f, delimiter="\t")
        if reader.fieldnames is None:
            raise RuntimeError("Merged TSV has no header.")
        if "method" not in reader.fieldnames:
            raise RuntimeError("Merged TSV is missing required column: method")

        for row in reader:
            method = row.get("method", "").strip()
            if not method:
                continue
            rows_by_method[method].append(row)

    if not rows_by_method:
        raise RuntimeError("No rows grouped by method were found in input TSV.")

    summary_rows = []

    for method in sorted(rows_by_method.keys()):
        rows = rows_by_method[method]

        out = {
            "method": method,
            "n_rows": len(rows),
            "n_unique_subjects": len(set(r.get("subject", "") for r in rows if r.get("subject", "") != "")),
            "n_unique_sessions": len(set(r.get("session", "") for r in rows if r.get("session", "") != "")),
        }

        for col in NUMERIC_COLUMNS:
            vals = [to_float(r.get(col)) for r in rows]
            stats = summarize(vals)
            out[f"{col}__n"] = stats["n"]
            out[f"{col}__mean"] = stats["mean"]
            out[f"{col}__median"] = stats["median"]
            out[f"{col}__min"] = stats["min"]
            out[f"{col}__max"] = stats["max"]
            out[f"{col}__stddev"] = stats["stddev"]

        # simple heuristic score for quick inspection:
        # reward face-shell removal, penalize brain removal more strongly
        face_removed_mean = out.get("pct_face_shell_removed__mean")
        brain_removed_mean = out.get("pct_brain_removed__mean")
        brain_altered_mean = out.get("pct_brain_altered__mean")

        if face_removed_mean != "" and brain_removed_mean != "" and brain_altered_mean != "":
            out["heuristic_score"] = (
                float(face_removed_mean)
                - 3.0 * float(brain_removed_mean)
                - 1.0 * float(brain_altered_mean)
            )
        else:
            out["heuristic_score"] = ""

        summary_rows.append(out)

    # stable header
    fixed = ["method", "n_rows", "n_unique_subjects", "n_unique_sessions"]
    metric_cols = []
    for col in NUMERIC_COLUMNS:
        metric_cols.extend([
            f"{col}__n",
            f"{col}__mean",
            f"{col}__median",
            f"{col}__min",
            f"{col}__max",
            f"{col}__stddev",
        ])
    header = fixed + metric_cols + ["heuristic_score"]

    with open(args.out_tsv, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=header, delimiter="\t")
        writer.writeheader()
        writer.writerows(summary_rows)

    payload = {
        "n_methods": len(summary_rows),
        "methods": summary_rows,
        "source_file": args.input,
    }

    with open(args.out_json, "w") as f:
        json.dump(payload, f, indent=2)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        raise