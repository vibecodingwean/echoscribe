#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"
exec ./scripts/setup_wizard.sh "$@"
