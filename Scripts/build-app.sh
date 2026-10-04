#!/bin/bash
set -euo pipefail
orbitshift_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec /usr/bin/python3 "$orbitshift_root/Scripts/build_app.py" "$@"
