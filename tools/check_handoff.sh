#!/usr/bin/env bash
# 校验交接文档与源码是否一致。
# 用法：在仓库根目录运行 bash tools/check_handoff.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/TodoWallpaper"
MAP="$ROOT/FILE_MAP.md"
missing=0

if [ ! -f "$MAP" ]; then
  echo "FAIL: 找不到 FILE_MAP.md"
  exit 1
fi

echo "== 1. 检查 FILE_MAP 登记的文件是否存在 =="
while IFS='|' read -r path target role types _rest; do
  case "$path" in *"|"*) ;; *) continue ;; esac
  path="$(echo "$path" | sed 's/^ *//; s/ *$//')"
  case "$path" in
    ""|\#*|---*|"路径") continue ;;
  esac
  if [ ! -f "$SRC/$path" ]; then
    echo "MISSING FILE: $path"
    missing=$((missing+1))
    continue
  fi
  # 2. 检查登记的主要类型名能否在该文件里找到
  first_type="$(echo "$types" | sed 's/^ *//; s/ *$//' | cut -d',' -f1 | sed 's/^ *//')"
  if [ -n "$first_type" ]; then
    if ! grep -q "$first_type" "$SRC/$path"; then
      echo "SYMBOL NOT FOUND: $first_type  in  $path"
      missing=$((missing+1))
    fi
  fi
done < "$MAP"

echo "== 2. 检查源码里是否有未登记的 .swift =="
while IFS= read -r f; do
  rel="${f#"$SRC"/}"
  if ! grep -q "| $rel |" "$MAP"; then
    echo "UNREGISTERED FILE: $rel"
    missing=$((missing+1))
  fi
done < <(find "$SRC" -name '*.swift' | sort)

echo "== 3. 检查 5 个文档是否齐全 =="
for doc in AGENTS.md ARCHITECTURE.md FILE_MAP.md KNOWN_ISSUES.md tools/check_handoff.sh; do
  [ -f "$ROOT/$doc" ] || { echo "MISSING DOC: $doc"; missing=$((missing+1)); }
done

echo
if [ "$missing" -eq 0 ]; then
  echo "PASS: 文档与源码一致（0 项问题）"
  exit 0
else
  echo "FAIL: $missing 项不一致"
  exit 1
fi
