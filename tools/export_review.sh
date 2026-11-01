#!/bin/bash
set -euo pipefail
# 用户按需导出，全部内容直接来自Git，不经模型转写。
ROOT=$(git rev-parse --show-toplevel)
BASE=${1:?用法: bash tools/export_review.sh 基线提交 [输出目录]}
DEST=${2:-"$PWD/review-export"}
git -C "$ROOT" rev-parse --verify "$BASE^{commit}" >/dev/null
mkdir -p "$DEST"
git -C "$ROOT" diff --no-ext-diff --binary "$BASE..HEAD" > "$DEST/CodeReview.txt"
FILES=()
while IFS= read -r -d '' ITEM; do
    case "$ITEM" in *.swift) FILES+=("$ITEM");; esac
done < <(git -C "$ROOT" ls-tree -r --name-only -z HEAD)
if [ "${#FILES[@]}" -eq 0 ]; then echo '没有Swift源码' >&2; exit 1; fi
git -C "$ROOT" archive --format=zip --output="$(cd "$DEST" && pwd)/SourceSnapshot.zip" HEAD -- "${FILES[@]}"
echo "已导出 $DEST/CodeReview.txt 与 $DEST/SourceSnapshot.zip"
