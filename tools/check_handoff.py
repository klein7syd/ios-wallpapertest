"""Target Membership：交接工具；严格校验引用与覆盖，不代替编译或真机验收。"""
from pathlib import Path, PurePosixPath
import argparse
import re


def check(root: Path) -> int:
    errors = []
    source = root / "TodoWallpaper"

    def read(path):
        try:
            return path.read_text(encoding="utf-8-sig")
        except (OSError, UnicodeError) as error:
            errors.append(f"无法读取 {path.relative_to(root)}：{error}")
            return ""

    def table(text, header, label):
        lines = text.splitlines()
        for index, line in enumerate(lines):
            if line.strip().startswith("|") and [part.strip() for part in line.strip().split("|")[1:-1]] == header:
                break
        else:
            errors.append(f"{label} 缺少表头")
            return []
        if index + 1 >= len(lines):
            errors.append(f"{label} 缺少分隔行")
            return []
        separator = lines[index + 1].strip()
        cells = [part.strip() for part in separator.split("|")[1:-1]]
        if not separator.startswith("|") or not separator.endswith("|") or len(cells) != len(header) or not all(re.fullmatch(r":?-{3,}:?", part) for part in cells):
            errors.append(f"{label} 分隔行不合法")
            return []
        rows = []
        for number, line in enumerate(lines[index + 2:], index + 3):
            value = line.strip()
            if not value or "|" not in value:
                break
            if not value.startswith("|") or not value.endswith("|"):
                errors.append(f"{label}:{number} 表格行边界不合法")
                continue
            cells = [part.strip() for part in value.split("|")[1:-1]]
            if len(cells) != len(header) or not all(cells):
                errors.append(f"{label}:{number} 列数或空列不合法")
                continue
            rows.append(cells)
        return rows

    def path_for(value):
        if value.startswith("`") and value.endswith("`") and value.count("`") == 2:
            value = value[1:-1]
        path = PurePosixPath(value)
        if not value or "\\" in value or ":" in value or "`" in value or path.is_absolute() or str(path) != value or ".." in path.parts or path.suffix != ".swift":
            errors.append(f"不合法源码路径：{value}")
            return None
        candidate = source / value
        if not candidate.resolve().is_relative_to(source.resolve()):
            errors.append(f"源码路径越界：{value}")
            return None
        return candidate

    def has_symbol(text, symbol):
        # 排除注释中的示例，类型/函数/属性须实际声明；点号引用逐段验证。
        text = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
        return all(re.search(r"\b(?:struct|class|enum|protocol|actor|typealias|associatedtype|func|let|var)\s+" + re.escape(part) + r"\b", text) for part in symbol.split("."))

    def report(title, count):
        print(title)
        print(f"检查了 {count} 条")
        if count == 0:
            errors.append(f"{title}：检查条数为 0")

    rows = table(read(root / "FILE_MAP.md"), ["路径", "Target", "职责", "主要类型"], "FILE_MAP")
    paths = set()
    texts = {}
    for value, target, role, symbols in rows:
        path = path_for(value)
        if path is None:
            continue
        relative = path.relative_to(source).as_posix()
        if relative in paths:
            errors.append(f"重复登记文件：{relative}")
        paths.add(relative)
        if not path.is_file():
            errors.append(f"缺少源码文件：{relative}")
        else:
            texts[relative] = read(path)
    report("== 1. FILE_MAP 文件存在 ==", len(rows))

    symbol_count = 0
    for value, target, role, values in rows:
        path = path_for(value)
        seen = set()
        for symbol in values.split(","):
            symbol = symbol.strip().strip("`")
            if not symbol:
                errors.append(f"空符号：{value}")
                continue
            symbol_count += 1
            if symbol in seen:
                errors.append(f"重复符号：{symbol} in {value}")
            seen.add(symbol)
            if not re.fullmatch(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*", symbol):
                errors.append(f"不合法符号：{symbol} in {value}")
            elif path is not None and not has_symbol(texts.get(path.relative_to(source).as_posix(), ""), symbol):
                errors.append(f"符号未声明：{symbol} in {value}")
    report("== 2. FILE_MAP 符号声明 ==", symbol_count)

    swift = sorted(path for path in source.rglob("*.swift") if path.is_file())
    for path in swift:
        relative = path.relative_to(source).as_posix()
        if relative not in paths:
            errors.append(f"未登记源码：{relative}")
        if not path.resolve().is_relative_to(source.resolve()):
            errors.append(f"源码路径越界：{relative}")
    report("== 3. Swift 源码登记覆盖 ==", len(swift))

    constants = table(read(root / "ARCHITECTURE.md"), ["名称", "值", "所在文件:函数", "含义"], "ARCHITECTURE 常量表")
    for name, value, reference, meaning in constants:
        match = re.fullmatch(r"`([^`]+\.swift):([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)`", reference)
        if match is None:
            errors.append(f"不合法常量引用：{reference}")
            continue
        filename, symbol = match.groups()
        path = path_for(filename)
        if path is not None:
            text = texts.get(filename)
            if text is None:
                text = read(path)
            if not has_symbol(text, symbol):
                errors.append(f"常量引用符号未声明：{reference}")
    report("== 4. ARCHITECTURE 常量引用 ==", len(constants))

    documents = ["AGENTS.md", "ARCHITECTURE.md", "FILE_MAP.md", "KNOWN_ISSUES.md", "tools/check_handoff.sh"]
    for document in documents:
        if not (root / document).is_file():
            errors.append(f"缺少交接文档：{document}")
    report("== 5. 交接文档齐全 ==", len(documents))
    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        print(f"FAIL: {len(errors)} 项问题")
        return 1
    print("PASS: 交接引用与源码登记检查通过（不代替编译、常量值语义审查或真机验证）")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    raise SystemExit(check(parser.parse_args().root.resolve()))
