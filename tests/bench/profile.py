#!/usr/bin/env python3
"""Slowest graph vertices of a Terraform run, from a trace log (see docs/testing.md).

    TF_LOG=trace TF_LOG_PATH=trace.log terraform -chdir=tests/bench/groups plan
    python3 tests/bench/profile.py trace.log

A vertex is a local, a variable (with its validations), an output (with its
preconditions) or a check; its time is from the start of its visit to its end.
"""

import argparse
import re
from datetime import datetime

LINE = re.compile(r'^(\S+) \[TRACE\] vertex "([^"]+)": (starting visit|visit complete)')


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("log", help="trace log (TF_LOG=trace TF_LOG_PATH=...)")
    parser.add_argument("--top", type=int, default=15, help="number of vertices to show")
    args = parser.parse_args()

    started, took = {}, {}
    with open(args.log, encoding="utf-8") as log:
        for line in log:
            match = LINE.match(line)
            if not match:
                continue
            stamp, vertex, event = match.groups()
            at = datetime.strptime(stamp[:23], "%Y-%m-%dT%H:%M:%S.%f")
            if event == "starting visit":
                started[vertex] = at
            elif vertex in started:
                took[vertex] = took.get(vertex, 0) + (at - started.pop(vertex)).total_seconds()

    for vertex, seconds in sorted(took.items(), key=lambda item: -item[1])[: args.top]:
        print(f"{seconds:8.2f} s  {vertex}")


if __name__ == "__main__":
    main()
