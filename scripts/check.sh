#!/usr/bin/env bash
set -euo pipefail
dir="$(cd "$(dirname "$0")/.." && pwd)"
"$dir/scripts/test.sh"
"$dir/scripts/smoke.sh"
"$dir/scripts/pills.sh"
"$dir/scripts/agents.sh"
"$dir/scripts/sides.sh"
"$dir/scripts/mapped.sh"
"$dir/scripts/lint.sh"
