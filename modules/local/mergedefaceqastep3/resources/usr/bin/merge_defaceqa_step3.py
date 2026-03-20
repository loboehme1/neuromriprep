#!/usr/bin/env python3

import argparse
import csv
import json
import os
import sys


def main():
    parser = argparse.ArgumentParser(description="Merge DefaceQA Step 3 TSV files.")
    parser.add_argument("--inputs", nargs="+", required=True, help="Input TSV files")
    parser.add_argument("--out-tsv", required=True, help="Merged TSV output")
    parser.add_argument("--out-json", required=True, help="Summary JSON output")
    args = parser.parse_args()

    rows = []
    header = None
    files_seen = []

    for path in sorted(args.inputs):
        files_seen.append(os.path.basename(path))

        with open(path, "r", newline="") as f:
            reader = csv.DictReader(f, delimiter="\t")
            current_header = reader.fieldnames

            if current_header is None:
                raise RuntimeError(f"No header found in TSV: {path}")

            if header is None:
                header = current_header
            elif current_header != header:
                raise RuntimeError(
                    f"Header mismatch in {path}\n"
                    f"Expected: {header}\n"
                    f"Found:    {current_header}"
                )

            file_rows = list(reader)
            if len(file_rows) == 0:
                continue

            for row in file_rows:
                row["_source_tsv"] = os.path.basename(path)
                rows.append(row)

    if header is None:
        raise RuntimeError("No valid TSV inputs found.")

    merged_header = header + ["_source_tsv"]

    with open(args.out_tsv, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=merged_header, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)

    summary = {
        "n_input_files": len(files_seen),
        "n_rows_merged": len(rows),
        "input_files": files_seen,
        "output_tsv": os.path.basename(args.out_tsv),
    }

    with open(args.out_json, "w") as f:
        json.dump(summary, f, indent=2)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[ERROR] {e}", file=sys.stderr)
        raise

