#!/usr/bin/env bash
set -euo pipefail

: "${TSB_TOOL_NAME:?TSB_TOOL_NAME is required}"
: "${TSB_TARGET_ID:?TSB_TARGET_ID is required}"
: "${TSB_OUTPUT_DIR:?TSB_OUTPUT_DIR is required}"

tool_script="/opt/tsb/tools/${TSB_TOOL_NAME}.sh"

if [[ ! -x "${tool_script}" ]]; then
  echo "missing tool script: ${tool_script}" >&2
  exit 1
fi

exec "${tool_script}"
