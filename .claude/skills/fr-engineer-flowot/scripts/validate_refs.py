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
  5. 三段式准入（成员页强制；00 路由页只查第 1 段）：
     5a. 「何时读」缺失                                                [error]
     5b. 无步骤/决策表（编号步骤、勾选清单、含步骤类标题、表格任一）   [error]
     5c. 无验证出口（验证类标题或 analyze/test/grep 等实际命令）       [error]
  6. 绝对 Windows 路径必须位于本仓库根，陈旧外仓路径                   [error]
     （跑全文含代码块——示例里也不该出现外仓路径；只覆盖反斜杠风格）
  7. 单文件超过 400 行拆分阈值                                         [warning]
  8. SKILL.md 入口文件缺失                                             [error]

链接类检查（1/2）在剥离 fenced code 与行内代码后的正文上进行，避免代码里的
数组索引（如 [[0, -1]]）和反引号内的假链接被误判；路径检查（6）有意跑全文。
三段式检查（5）：5b/5c 豁免 00 路由页——路由页本身是动线表（诉求决策表），
不承载操作步骤；SKILL.md 不参与三段式。

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
ROUTER_RE = re.compile(r"^[A-H]00-")
STEP_RE = re.compile(r"^\s*\d+\.\s+\S", re.MULTILINE)
CHECKBOX_RE = re.compile(r"^\s*- \[.\]", re.MULTILINE)
STEP_HEADING_RE = re.compile(r"^#{1,4}\s.*(?:步骤|SOP|工作流|Checklist|清单|检查表|动线)", re.MULTILINE)
TABLE_ROW_MIN = 3
VERIFY_HEADING_RE = re.compile(r"^#{1,4}\s.*(?:验证出口|验证|自检|回归|检查)", re.MULTILINE)
VERIFY_CMD_RE = re.compile(r"flutter analyze|flutter test|grep -|validate_refs|退出码|golden")


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


def has_sop_body(text: str) -> bool:
    """三段式第 2 段：步骤/决策表信号（编号步骤、勾选清单、步骤类标题、表格）。"""
    if STEP_RE.search(text) or CHECKBOX_RE.search(text) or STEP_HEADING_RE.search(text):
        return True
    table_rows = sum(
        1 for line in text.splitlines() if line.strip().startswith("|") and not line.strip().startswith("|--")
    )
    return table_rows >= TABLE_ROW_MIN


def has_verify_exit(prose_text: str, full_text: str) -> bool:
    """三段式第 3 段：验证类标题，或 analyze/test/grep 等实际验证命令。"""
    return bool(VERIFY_HEADING_RE.search(prose_text) or VERIFY_CMD_RE.search(full_text))


def check_sop_form(text: str, prose_text: str, path: Path, errors: list[str]) -> None:
    is_router = bool(ROUTER_RE.match(path.name))
    if not WHEN_READ_RE.search(text):
        errors.append(f"{path.name}: 三段式缺「何时读」（第 1 段）")
    if is_router:
        return  # 路由页只查第 1 段：动线表即其决策表，不承载操作步骤
    if not has_sop_body(text):
        errors.append(f"{path.name}: 三段式缺步骤/决策表（第 2 段）")
    if not has_verify_exit(prose_text, text):
        errors.append(f"{path.name}: 三段式缺验证出口（第 3 段）")


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

        body = prose(text)
        if path.name != "SKILL.md":
            check_sop_form(text, body, path, errors)
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
