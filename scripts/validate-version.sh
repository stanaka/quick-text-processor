#!/bin/bash
set -euo pipefail

version=${1:-}
if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "error: version must be X.Y.Z with no leading zeros (for example, 0.1.0)" >&2
    exit 1
fi
