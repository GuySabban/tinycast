#!/bin/bash
set -eu
exec node "$(dirname "$0")/owner-checks.mjs" "$@"
