#!/bin/sh
# Runs all pure-logic tests (see tools/run_tests.py). Needs `luau` and python3 on PATH.
exec python3 "$(dirname "$0")/run_tests.py" "$@"
