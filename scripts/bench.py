#!/usr/bin/env python3
"""Measure core plans and compare time and peak memory with a CI baseline.

    python3 scripts/bench.py --json results.json
    python3 scripts/bench.py --update
"""

import argparse
import json
import math
import os
import pathlib
import platform
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
WORKLOADS = {
    "plain": {"hosts": 500},
    "groups": {"hosts": 500, "groups": 10},
    "import": {"hosts": 1000},
}
FACTOR = 2.0


def measure(name, variables):
    command = ["terraform", f"-chdir={ROOT / 'tests/bench' / name}"]
    init = subprocess.run(
        command + ["init", "-input=false", "-no-color"],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    if init.returncode:
        raise RuntimeError(f"{name}: terraform init failed\n{init.stdout}")

    with tempfile.TemporaryFile(mode="w+") as output:
        started = time.monotonic()
        child = subprocess.Popen(
            command + ["plan", "-input=false", "-lock=false", "-no-color"]
            + [f"-var={key}={value}" for key, value in variables.items()],
            stdout=output, stderr=subprocess.STDOUT,
        )
        _, status, usage = os.wait4(child.pid, 0)
        seconds = time.monotonic() - started
        # Popen must not reap the child again after wait4 collected its usage.
        child.returncode = os.waitstatus_to_exitcode(status)
        if child.returncode:
            output.seek(0)
            raise RuntimeError(f"{name}: terraform plan failed\n{output.read()}")

    divisor = 1024 * 1024 if sys.platform == "darwin" else 1024
    return {"vars": variables, "seconds": seconds, "memory_mib": usage.ru_maxrss / divisor}


def write_results(path, results):
    path.write_text(json.dumps(results, indent=2) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--baseline", type=pathlib.Path, default=ROOT / "tests/bench/baseline.json")
    parser.add_argument("--factor", type=float, default=FACTOR, help="blocking slowdown factor (default: 2)")
    parser.add_argument("--json", type=pathlib.Path, help="write results in baseline format")
    parser.add_argument("--summary", type=pathlib.Path, help="append a Markdown summary")
    parser.add_argument("--update", action="store_true", help="update the baseline with this run's results")
    parser.add_argument("--only", action="append", choices=WORKLOADS, help="workload to run (repeatable)")
    args = parser.parse_args()
    if not math.isfinite(args.factor) or args.factor <= 0:
        parser.error("--factor must be finite and positive")

    messages = []

    def report(message):
        messages.append(message)
        print(message)

    try:
        if args.baseline.exists():
            baseline = json.loads(args.baseline.read_text(encoding="utf-8"))
        else:
            report(f"Warning: baseline {args.baseline} does not exist")
            baseline = {"workloads": {}}
        version = json.loads(subprocess.check_output(
            ["terraform", "version", "-json"], text=True,
        ))["terraform_version"]
        if baseline.get("terraform_version") not in (None, version):
            report(f"Warning: Terraform {version}, baseline uses {baseline['terraform_version']}")
        note = "GitHub ubuntu-latest" if os.environ.get("GITHUB_ACTIONS") == "true" else platform.platform()
        results = {"terraform_version": version, "platform": note, "workloads": {}}
        print(f"Terraform {version}, {note}")
        rows = []
        failed = False
        for name, variables in WORKLOADS.items():
            if args.only and name not in args.only:
                continue
            print(f"Running {name}...", flush=True)
            current = measure(name, variables)
            results["workloads"][name] = current
            previous = baseline["workloads"].get(name)
            if previous is None or previous.get("vars") != variables:
                reason = "missing workload" if previous is None else "different sizes"
                report(f"Warning: {name}: {reason} in baseline, comparison skipped")
                previous = None
            cells = [name, ", ".join(f"{key}={value}" for key, value in variables.items())]
            for metric in ("seconds", "memory_mib"):
                cells.append(f"{current[metric]:.2f}")
                if previous is None:
                    cells.extend(["-", "-"])
                    continue
                reference = previous[metric]
                if not math.isfinite(reference) or reference <= 0:
                    raise ValueError(f"{name}: baseline {metric} must be finite and positive")
                ratio = current[metric] / reference
                cells.extend([f"{reference:.2f}", f"{ratio:.2f}x"])
                if ratio > args.factor:
                    report(f"FAIL: {name}: {metric} is {ratio:.2f}x baseline (limit {args.factor:g}x)")
                    failed = True
            rows.append("| " + " | ".join(cells) + " |")
        table = "\n".join([
            "| Workload | Size | Time (s) | Baseline (s) | Ratio | Memory (MiB) | Baseline (MiB) | Ratio |",
            "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |",
            *rows,
        ])
        print("\n" + table)
        if args.summary:
            with args.summary.open("a", encoding="utf-8") as summary:
                summary.write(f"\n## Benchmarks\n\nTerraform {version}, {note}\n\n")
                if messages:
                    summary.write("\n".join(f"- {message}" for message in messages) + "\n\n")
                summary.write(table + "\n")
        if args.json:
            write_results(args.json, results)
        if args.update:
            updated = results
            if args.only:
                updated = {
                    **baseline, **results,
                    "workloads": {**baseline["workloads"], **results["workloads"]},
                }
                updated.pop("note", None)
            write_results(args.baseline, updated)
        return int(failed)
    except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError, RuntimeError) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
