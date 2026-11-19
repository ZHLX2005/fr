#!/usr/bin/env python3
"""validate_refs.py — fr-engineer-flowot skill 文档完整性校验。

检查项（error 拦截 / warning 提示）：
  1. wikilink [[目标]] 必须指向 references/ 内真实存在的 .md          [error]
  2. 《Xnn-yyy》形式的跨序列引用必须指向真实存在的 .md                 [error]
     （仅当形如「序列码-名字」才算文件引用；《需求动线表》等节名不检查）
  3. frontmatter：name 与文件名 stem 不符                              [error]
     （frontmatter 形态存疑或无 name 字段按缺失处理                    [warning]——
       首行 `---` 分隔线易被误认成 frontmatter，歧义场景不拦截）
  4. frontmatter 缺失                                                  [warning]
  5. 成员页找不到「何时读」表述（三段式第 1 段）                       [warning]
  6. 绝对 Windows 路径必须位于本仓库根，陈旧外仓路径                   [error]
     （跑全文含代码块——示例里也不该出现外仓路径；只覆盖反斜杠风格）
  7. 单文件超过 400 行拆分阈值                                         [warning]
  8. SKILL.md 入口文件缺失                                             [error]

链接类检查（1/2）在剥离 fenced code 与行内代码后的正文上进行，避免代码里的
数组索引（如 [[0, -1]]）和反引号内的假链接被误判；路径检查（6）有意跑全文。

用法：python scripts/validate_refs.py
退出码：0 = 通过（允许 warning）；1 = 存在 error
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent.parent
REF_DIR = SKILL_DIR / "references"
SKILL_ENTRY = SKILL_DIR / "SKILL.md"
ALLOWED_ROOTS = ("D:\\DevProjects\\my\\github\\fr",)
LINE_LIMIT = 400

WIKILINK_RE = re.compile(r"\[\[([^\]|#]+)")
CJK_FILE_RE = re.compile(r"《([A-Z][a-z]?\d{2}[-\s][^§》《]+)》")
WINPATH_RE = re.compile(r"[A-Za-z]:\\[^\s`》」』）)，。；:*]*")
FRONT_NAME_RE = re.compile(r"^name:\s*(.+?)\s*$", re.MULTILINE)
FRONTMATTER_RE = re.compile(r"\A---\s*\n(.*?)\n---\s*\n", re.DOTALL)
WHEN_READ_RE = re.compile(r"何时读")


def collect_files() -> list[Path]:
    """SKILL.md + references/ 下全部 .md。"""
    files = [SKILL_ENTRY]
    files += sorted(p for p in REF_DIR.glob("*.md") if p.is_file())
    return files


def normalize_ref(name: str) -> str:
    """分隔符无关比较：《Ea02 token 字典》与 Ea02-token字典 视为同一目标。"""
    return re.sub(r"[\s\-－—]+", "", name.strip())


def prose(text: str) -> str:
    """剥离 fenced code block 与行内代码后的正文。

    围栏按行扫描开关，免疫未闭合围栏、围栏内含 ```、4+ 反引号等边角；
    未闭合围栏退化为「其余全是代码」——宁可漏检也不误报。
    """
    kept: list[str] = []
    in_fence = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            continue
        if not in_fence:
            kept.append(line)
    return re.sub(r"`[^`\n]+`", "", "\n".join(kept))


def in_allowed_roots(winpath: str) -> bool:
    """前缀匹配但要求路径边界：D:\\...\\fr-backup 不得冒充本仓。"""
    upper = winpath.upper()
    return any(
        upper == root_upper or upper.startswith(root_upper + "\\")
        for root_upper in (root.upper() for root in ALLOWED_ROOTS)
    )


def check_wikilinks(text: str, path: Path, known: set[str], errors: list[str]) -> None:
    for target in WIKILINK_RE.findall(text):
        name = target.strip()
        if normalize_ref(name) not in known:
            errors.append(f"{path.name}: 断链 wikilink [[{name}]]")


def check_cjk_refs(text: str, path: Path, known: set[str], errors: list[str]) -> None:
    for raw in CJK_FILE_RE.findall(text):
        if normalize_ref(raw) not in known:
            errors.append(f"{path.name}: 断链跨序列引用《{raw}》")


def check_winpaths(text: str, path: Path, errors: list[str]) -> None:
    for winpath in WINPATH_RE.findall(text):
        if not in_allowed_roots(winpath):
            errors.append(f"{path.name}: 非本仓绝对路径 {winpath}")


def check_frontmatter(text: str, path: Path, errors: list[str], warnings: list[str]) -> None:
    match = FRONTMATTER_RE.match(text)
    if not match:
        warnings.append(f"{path.name}: 缺 frontmatter（name/description）")
        return
    head = match.group(1)
    name_match = FRONT_NAME_RE.search(head)
    if not name_match:
        # 首行 `---` 分隔线可能被误认成 frontmatter 头，无 name 时按缺失处理，不拦截。
        warnings.append(f"{path.name}: frontmatter 形态存疑或无 name 字段（按缺失处理）")
    elif name_match.group(1).strip() != path.stem:
        errors.append(
            f"{path.name}: frontmatter name「{name_match.group(1)}」≠ 文件名 stem「{path.stem}」"
        )


def main() -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    files = collect_files()
    known = {normalize_ref(p.stem) for p in REF_DIR.glob("*.md")}
    errors: list[str] = []
    warnings: list[str] = []

    if not SKILL_ENTRY.exists():
        errors.append("SKILL.md 入口文件缺失")
        files = [p for p in files if p != SKILL_ENTRY]

    for path in files:
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError as exc:
            errors.append(f"{path.name}: 非 UTF-8 编码（{exc}）")
            continue

        line_count = len(text.splitlines())
        if line_count > LINE_LIMIT:
            warnings.append(f"{path.name}: {line_count} 行 > {LINE_LIMIT} 拆分阈值")

        if path.name != "SKILL.md":
            check_frontmatter(text, path, errors, warnings)
            if not WHEN_READ_RE.search(text):
                warnings.append(f"{path.name}: 未找到「何时读」表述（三段式第 1 段）")

        body = prose(text)
        check_wikilinks(body, path, known, errors)
        check_cjk_refs(body, path, known, errors)
        check_winpaths(text, path, errors)

    for warning in warnings:
        print(f"WARN  {warning}")
    for error in errors:
        print(f"ERROR {error}")
    print(f"\n{len(files)} 个文件：{len(errors)} error / {len(warnings)} warning")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
