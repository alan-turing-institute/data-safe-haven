#!/usr/bin/env bash
# Backward-compatible wrapper for the Mustache lint renderer.
set -euo pipefail
exec python3 "$(dirname "$0")/expand_mustache.py" --in-place
