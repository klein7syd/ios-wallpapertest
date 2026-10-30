#!/usr/bin/env bash
# Target Membership：交接检查工具；每项计数与失败处理由同目录 Python 实现。
set -euo pipefail
HANDOFF_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Windows 的 python3 可能是商店占位程序；只探测解释器，绝不吞掉检查器的失败。
for HANDOFF_PYTHON in python3 python; do
  if command -v "$HANDOFF_PYTHON" >/dev/null 2>&1 && "$HANDOFF_PYTHON" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
    exec "$HANDOFF_PYTHON" -X utf8 "$HANDOFF_ROOT/tools/check_handoff.py" --root "$HANDOFF_ROOT"
  fi
done
echo 'FAIL: 交接检查需要 Python 3.9 或更新版本。' >&2
exit 1
