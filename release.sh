#!/usr/bin/env bash
set -euo pipefail

python scripts/publish_docker.py --push "$@"
