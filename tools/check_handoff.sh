#!/usr/bin/env bash
# 校验交接文档与源码是否一致。
# 用法：在仓库根目录运行 bash tools/check_handoff.sh
#
# 过滤规则（上次为消除误报而加）：
#   1) FILE_MAP.md 的循环里，凡是不含 "|" 的行一律跳过（标题、说明句、分隔线）。
#      上次的误报就是那行中文说明句被当成表格行解析。
#   2) 表格分隔行按表头关键字跳过，不当文件处理。
#   这两条只过滤「非表格行」，真实文件行一定带 "|"，所以不会放过真实缺漏。
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/TodoWallpaper"
MAP="$ROOT/FILE_MAP.md"
ARCH="$ROOT/ARCHITECTURE.md"
problems=0

fail() { echo "$1"; problems=$((problems+1)); }

[ -f "$MAP" ] || { echo "FAIL: 找不到 FILE_MAP.md"; exit 1; }
[ -f "$ARCH" ] || { echo "FAIL: 找不到 ARCHITECTURE.md"; exit 1; }

echo "== 1. FILE_MAP：文件是否存在 =="
while IFS='|' read -r path target role types _rest; do
  case "$path" in *"|"*) ;; *) continue ;; esac
  path="$(echo "$path" | sed 's/^ *//; s/ *$//')"
  case "$path" in ""|"路径"|"---"*) continue ;; esac
  [ -f "$SRC/$path" ] || fail "MISSING FILE: $path"
done < "$MAP"

echo "== 2. FILE_MAP：每个类型/函数名能否在对应文件里找到 =="
: > /tmp/handoff_symbols.txt
while IFS='|' read -r path target role types _rest; do
  case "$path" in *"|"*) ;; *) continue ;; esac
  path="$(echo "$path" | sed 's/^ *//; s/ *$//')"
  case "$path" in ""|"路径"|"---"*) continue ;; esac
  [ -f "$SRC/$path" ] || continue
  echo "$types" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | while IFS= read -r sym; do
    [ -z "$sym" ] && continue
    grep -q "$sym" "$SRC/$path" || echo "SYMBOL NOT FOUND: $sym  in  $path" >> /tmp/handoff_symbols.txt
  done
done < "$MAP"
if [ -s /tmp/handoff_symbols.txt ]; then cat /tmp/handoff_symbols.txt; problems=$((problems+$(wc -l < /tmp/handoff_symbols.txt))); fi

echo "== 3. 源码里是否有未登记的 .swift =="
while IFS= read -r f; do
  rel="${f#"$SRC"/}"
  grep -q "| $rel |" "$MAP" || fail "UNREGISTERED FILE: $rel"
done < <(find "$SRC" -name '*.swift' | sort)

echo "== 4. ARCHITECTURE 常量表：文件存在 + 符号可 grep =="
: > /tmp/handoff_table.txt
grep -E '^\|.*`[^`]+\.swift:[A-Za-z_][A-Za-z0-9_.]*`' "$ARCH" | while IFS= read -r row; do
  ref="$(echo "$row" | grep -oE '`[^`]+\.swift:[A-Za-z_][A-Za-z0-9_.]*`' | head -1 | tr -d '`')"
  [ -z "$ref" ] && continue
  file="${ref%%:*}"
  sym="${ref##*:}"
  full="$SRC/$file"
  if [ ! -f "$full" ]; then echo "MISSING FILE: $file" >> /tmp/handoff_table.txt; continue; fi
  grep -q "${sym%%.*}" "$full" || echo "SYMBOL NOT FOUND: $sym  in  $file" >> /tmp/handoff_table.txt
done
if [ -s /tmp/handoff_table.txt ]; then cat /tmp/handoff_table.txt; problems=$((problems+$(wc -l < /tmp/handoff_table.txt))); fi

echo "== 5. 交接文档是否齐全 =="
for doc in AGENTS.md ARCHITECTURE.md FILE_MAP.md KNOWN_ISSUES.md tools/check_handoff.sh; do
  [ -f "$ROOT/$doc" ] || fail "MISSING DOC: $doc"
done

echo
if [ "$problems" -eq 0 ]; then
  echo "PASS: 文档与源码一致（0 项问题）"
  exit 0
else
  echo "FAIL: $problems 项不一致"
  exit 1
fi
