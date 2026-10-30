"""Target Membership：独立 Python 原生工具回归；只修改临时夹具。"""
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

CHECKER = Path(__file__).with_name("check_handoff.py")


class HandoffChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="handoff-checks-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.write("TodoWallpaper/App/A.swift", "struct Alpha {}\nenum Beta {}\n")
        self.write("TodoWallpaper/Core/B.swift", "enum Gamma {}\n")
        self.write("FILE_MAP.md", "# FILE_MAP\n\n| 路径 | Target | 职责 | 主要类型 |\n| --- | --- | --- | --- |\n| App/A.swift | App | 测试 | Alpha, Beta |\n| Core/B.swift | App + Widget | 测试 | Gamma |\n")
        self.write("ARCHITECTURE.md", "# ARCHITECTURE\n\n| 名称 | 值 | 所在文件:函数 | 含义 |\n| --- | --- | --- | --- |\n| 测试常量 | 1 | `Core/B.swift:Gamma` | 测试 |\n")
        for name in ["AGENTS.md", "KNOWN_ISSUES.md", "tools/check_handoff.sh"]:
            self.write(name, "测试\n")

    def write(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def replace(self, name, before, after):
        self.write(name, (self.root / name).read_text(encoding="utf-8").replace(before, after))

    def run_check(self, expected, message=None):
        result = subprocess.run([sys.executable, "-X", "utf8", str(CHECKER), "--root", str(self.root)], capture_output=True, encoding="utf-8")
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        self.assertEqual(len(re.findall(r"检查了 \d+ 条", result.stdout)), 5, result.stdout)
        if message:
            self.assertIn(message, result.stdout)
        return result.stdout

    def test_valid_actual_counts(self):
        output = self.run_check(0)
        self.assertEqual(re.findall(r"检查了 (\d+) 条", output), ["2", "3", "2", "1", "5"])

    def test_counts_follow_added_file(self):
        self.write("TodoWallpaper/Core/C.swift", "struct Delta {}")
        with (self.root / "FILE_MAP.md").open("a", encoding="utf-8") as stream:
            stream.write("| Core/C.swift | App + Widget | 测试 | Delta |\n")
        self.assertEqual(re.findall(r"检查了 (\d+) 条", self.run_check(0)), ["3", "4", "3", "1", "5"])

    def test_missing_file(self):
        (self.root / "TodoWallpaper/App/A.swift").unlink()
        self.run_check(1, "缺少源码文件")

    def test_missing_symbol(self):
        self.replace("TodoWallpaper/App/A.swift", "Alpha", "Different")
        self.run_check(1, "符号未声明：Alpha")

    def test_comment_is_not_declaration(self):
        self.write("TodoWallpaper/App/A.swift", "// struct Alpha {}\nenum Beta {}")
        self.run_check(1, "符号未声明：Alpha")

    def test_unknown_source(self):
        self.write("TodoWallpaper/App/Unknown.swift", "struct Unknown {}")
        self.run_check(1, "未登记源码")

    def test_empty_map(self):
        self.write("FILE_MAP.md", "# 空表\n")
        self.run_check(1, "检查条数为 0")

    def test_empty_source(self):
        for path in (self.root / "TodoWallpaper").rglob("*.swift"):
            path.unlink()
        self.run_check(1, "== 3. Swift 源码登记覆盖 ==：检查条数为 0")

    def test_empty_constants(self):
        self.write("ARCHITECTURE.md", "# 无常量\n")
        self.run_check(1, "== 4. ARCHITECTURE 常量引用 ==：检查条数为 0")

    def test_empty_symbols(self):
        self.replace("FILE_MAP.md", "Alpha, Beta", " ")
        self.replace("FILE_MAP.md", "Gamma", " ")
        self.run_check(1, "== 2. FILE_MAP 符号声明 ==：检查条数为 0")

    def test_missing_row(self):
        self.replace("FILE_MAP.md", "| App/A.swift | App | 测试 | Alpha, Beta |\n", "")
        self.run_check(1, "未登记源码：App/A.swift")

    def test_malformed_row(self):
        self.replace("FILE_MAP.md", "| App/A.swift | App | 测试 | Alpha, Beta |", "App/A.swift | App | 测试 | Alpha, Beta |")
        self.run_check(1, "表格行边界不合法")

    def test_traversal(self):
        self.replace("FILE_MAP.md", "App/A.swift", "../outside.swift")
        self.run_check(1, "不合法源码路径")

    def test_duplicate_row(self):
        self.replace("FILE_MAP.md", "Core/B.swift", "App/A.swift")
        self.run_check(1, "重复登记文件")

    def test_duplicate_symbol(self):
        self.replace("FILE_MAP.md", "Alpha, Beta", "Alpha, Alpha")
        self.run_check(1, "重复符号")

    def test_missing_constant_symbol(self):
        self.replace("ARCHITECTURE.md", "B.swift:Gamma", "B.swift:Missing")
        self.run_check(1, "常量引用符号未声明")

    def test_malformed_constant(self):
        self.replace("ARCHITECTURE.md", "`Core/B.swift:Gamma`", "Core/B.swift")
        self.run_check(1, "不合法常量引用")

    def test_missing_document(self):
        (self.root / "AGENTS.md").unlink()
        self.run_check(1, "缺少交接文档")


if __name__ == "__main__":
    unittest.main(verbosity=2)
