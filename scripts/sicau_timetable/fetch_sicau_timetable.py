#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
SICAU 教务系统课表抓取脚本（无 AI 参与版）

功能：
  1. 用户输入学号 + 密码
  2. 自动登录 https://jiaowu.sicau.edu.cn
  3. 进入 2025-2026-2 学期 -> 选课情况(课表)
  4. 抓取课程表并转换为本项目 DSL 格式
     (DSL 规范见 lib/core/timetable/DSL_FORMAT.md)

依赖： requests, beautifulsoup4
安装： pip install requests beautifulsoup4

用法：
  python fetch_sicau_timetable.py --user 202308648 --password zhaozhao11
  python fetch_sicau_timetable.py --user 202308648 --password zhaozhao11 \
      --semester 2025-2026-2 --output timetable_dsl.txt
"""

import argparse
import json
import re
import sys
from typing import Dict, List, Optional, Tuple

try:
    import requests
    from bs4 import BeautifulSoup
except ImportError:
    print("缺少依赖，请先运行： pip install requests beautifulsoup4", file=sys.stderr)
    sys.exit(1)


# ----------------------------- 常量 -----------------------------

BASE = "https://jiaowu.sicau.edu.cn"
LOGIN_PAGE = f"{BASE}/web/web/web/index.asp"
LOGIN_POST = f"{BASE}/jiaoshi/bangong/check.asp"
SEMESTER_PAGE = f"{BASE}/xuesheng/gongxuan/gongxuan/xszhinan.asp"
TIMETABLE_PAGE = f"{BASE}/xuesheng/gongxuan/gongxuan/kbbanji.asp"

# 默认抓取学期，可通过 --semester 覆盖
DEFAULT_SEMESTER = "2025-2026-2"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "zh-CN,zh;q=0.9",
}

# 列名到数据字段映射
COLUMN_NAMES = [
    "校区", "课程名称", "编号", "周次", "教室", "上课时间",
    "学分", "学时", "周学时", "实验周学时", "考核方法",
    "教师", "选课方式", "混合式教学",
]


# ----------------------------- 登录 -----------------------------

def login(session: requests.Session, user: str, password: str) -> None:
    """模拟登录教务处，返回登录后的 session（带 ASPSESSIONID cookie）"""
    # 1. 拉取登录页：拿到 sign / hour_key 这两个动态 token
    r = session.get(LOGIN_PAGE, headers=HEADERS, timeout=15)
    r.raise_for_status()
    r.encoding = r.apparent_encoding  # 中文页面 encoding 兜底

    soup = BeautifulSoup(r.text, "html.parser")
    form = soup.find("form", attrs={"name": "form1"})
    if not form:
        raise RuntimeError("登录页未找到 form1，请检查登录页 URL 或网络")

    sign = form.find("input", attrs={"name": "sign"})
    hour_key = form.find("input", attrs={"name": "hour_key"})
    if not sign or not hour_key:
        raise RuntimeError("登录页缺少 sign / hour_key 隐藏字段")

    sign_val = sign.get("value", "")
    hour_key_val = hour_key.get("value", "")

    # 2. POST 凭据 + 隐藏字段 + 学生身份
    payload = {
        "user": user,
        "pwd": password,
        "lb": "S",          # 学生；教师改成 "T"
        "sign": sign_val,
        "hour_key": hour_key_val,
        "submit": "",
    }
    r = session.post(
        LOGIN_POST,
        data=payload,
        headers={**HEADERS, "Content-Type": "application/x-www-form-urlencoded",
                 "Referer": LOGIN_PAGE},
        allow_redirects=True,
        timeout=15,
    )
    r.raise_for_status()
    r.encoding = r.apparent_encoding

    # 3. 校验是否真的登录成功：登录后页面里包含学号或“学生-课业信息”
    if "index1.asp" not in r.url and "学生-课业信息" not in r.text and user not in r.text:
        # 尝试拿一个错误提示
        m = re.search(r"alert\(['\"]([^'\"]+)", r.text) or re.search(
            r"<font[^>]*color=red[^>]*>([^<]+)</font>", r.text
        )
        msg = m.group(1) if m else "登录失败，可能是学号/密码错误"
        raise RuntimeError(f"登录失败：{msg}")


# ----------------------------- 抓课表 -----------------------------

def fetch_timetable_html(session: requests.Session, semester: str) -> str:
    """登录后跳到指定学期的选课情况(课表)页面，返回 HTML 字符串"""
    # 中转页：切换学期
    r = session.get(
        SEMESTER_PAGE,
        params={"title_id1": "9", "xueqi": semester},
        headers=HEADERS,
        timeout=15,
    )
    r.raise_for_status()
    r.encoding = r.apparent_encoding

    # 真实课表页
    r = session.get(
        TIMETABLE_PAGE,
        params={"title_id1": "4"},
        headers=HEADERS,
        timeout=15,
    )
    r.raise_for_status()
    r.encoding = r.apparent_encoding
    return r.text


def parse_courses(html: str) -> List[Dict[str, str]]:
    """从课表页 HTML 中提取课程行，每行是一个 dict"""
    soup = BeautifulSoup(html, "html.parser")
    tables = soup.find_all("table")

    # 找那张“校区 课程名称 编号 …”的明细表
    target = None
    for t in tables:
        head = "".join(t.find("tr").get_text() for _ in [0]) if t.find("tr") else ""
        # 兼容 BeautifulSoup 不同的取法
        first_row = t.find("tr")
        head = first_row.get_text(" ", strip=True) if first_row else ""
        if "课程名称" in head and "编号" in head:
            target = t
            break
    if not target:
        raise RuntimeError("未找到课表明细表（包含 课程名称/编号 列的 table）")

    rows = target.find_all("tr")
    # 第一行是表头
    if len(rows) < 2:
        raise RuntimeError("课表为空")

    header_cells = [c.get_text(" ", strip=True) for c in rows[0].find_all(["th", "td"])]
    if header_cells[:2] != ["校区", "课程名称"]:
        # 实际表头可能和 COLUMN_NAMES 一致，按 COLUMN_NAMES 对齐
        header_cells = COLUMN_NAMES

    courses: List[Dict[str, str]] = []
    for tr in rows[1:]:
        cells = [c.get_text(" ", strip=True) for c in tr.find_all(["th", "td"])]
        if not cells or not cells[1]:  # 课程名称空行跳过
            continue
        # 补齐 / 截断到列数
        cells = (cells + [""] * len(header_cells))[: len(header_cells)]
        record = dict(zip(header_cells, cells))
        courses.append(record)
    return courses


# ----------------------------- DSL 转换 -----------------------------

def parse_week_range(week_field: str) -> List[int]:
    """
    把 "1-14" / "7,9,11" / "1-16(单)" 这种字符串转成具体周次列表。
    """
    week_field = week_field.strip()
    if not week_field:
        return []

    parity = None
    m = re.search(r"[(（]([单双])[)）]", week_field)
    if m:
        parity = m.group(1)  # 单 / 双
        week_field = re.sub(r"[(（][单双][)）]", "", week_field)

    weeks: List[int] = []
    for part in week_field.split(","):
        part = part.strip()
        if not part:
            continue
        if "-" in part:
            try:
                a, b = part.split("-", 1)
                a, b = int(a), int(b)
                weeks.extend(range(min(a, b), max(a, b) + 1))
            except ValueError:
                continue
        else:
            try:
                weeks.append(int(part))
            except ValueError:
                continue

    if parity == "单":
        weeks = [w for w in weeks if w % 2 == 1]
    elif parity == "双":
        weeks = [w for w in weeks if w % 2 == 0]
    return sorted(set(weeks))


def parse_time_segments(time_field: str) -> List[Tuple[int, int, int, Optional[str]]]:
    """
    把 "2-9,2-10(单) 4-5,4-6" 这种上课时间字符串拆成段。
    返回: [(day, slot_start, slot_end, parity or None), ...]
          parity: '单' / '双' / None
    """
    if not time_field or not time_field.strip():
        return []

    segments: List[Tuple[int, int, int, Optional[str]]] = []
    # 兼容换行/空格分割
    for chunk in re.split(r"[\s\n]+", time_field.strip()):
        if not chunk:
            continue
        parity = None
        m = re.search(r"[(（]([单双])[)）]", chunk)
        if m:
            parity = m.group(1)
            chunk = re.sub(r"[(（][单双][)）]", "", chunk)

        # 单段形如 "2-9,2-10"，可能多个 day-slot
        slots: List[Tuple[int, int]] = []  # (day, slot)
        for token in chunk.split(","):
            token = token.strip()
            if not token:
                continue
            mm = re.match(r"^(\d+)\s*[-—]\s*(\d+)$", token)
            if not mm:
                continue
            day, slot = int(mm.group(1)), int(mm.group(2))
            slots.append((day, slot))

        if not slots:
            continue

        days = {d for d, _ in slots}
        slot_nums = [s for _, s in slots]
        slot_start, slot_end = min(slot_nums), max(slot_nums)
        # 如果出现多个 day，拆成多段
        for d in sorted(days):
            segments.append((d, slot_start, slot_end, parity))
    return segments


def split_multi(value: str) -> List[str]:
    """教室 / 教师字段可能多值，按空白分割"""
    if not value:
        return [""]
    parts = re.split(r"[\s\n]+", value.strip())
    return [p for p in parts if p] or [""]


def weeks_to_dsl(weeks: List[int]) -> str:
    """[1,3,5,7,9,11,13] -> 'w1,3,5,7,9,11,13' 或 'w1-14'"""
    if not weeks:
        return ""
    # 连续段合并
    runs: List[List[int]] = []
    for w in weeks:
        if runs and runs[-1][-1] == w - 1:
            runs[-1].append(w)
        else:
            runs.append([w])

    parts: List[str] = []
    for run in runs:
        if len(run) == 1:
            parts.append(str(run[0]))
        elif len(run) == 2:
            parts.append(f"{run[0]},{run[1]}")
        else:
            parts.append(f"{run[0]}-{run[-1]}")
    return "w" + ",".join(parts)


def course_to_dsl_lines(course: Dict[str, str]) -> List[str]:
    """单条课程记录 -> 多行 DSL（按 (day, slot) 拆分）"""
    name = (course.get("课程名称") or "").strip()
    teacher = (course.get("教师") or "").strip()
    classrooms = split_multi(course.get("教室") or "")
    week_field = course.get("周次") or ""
    time_field = course.get("上课时间") or ""

    base_weeks = parse_week_range(week_field)
    segments = parse_time_segments(time_field)

    lines: List[str] = []
    if not segments:
        # 没有具体时间（如“自行在线学习”），仍保留一行 w1-X
        weeks_str = weeks_to_dsl(base_weeks)
        parts = [name, "@", "1", "1", weeks_str]
        if classrooms and classrooms[0]:
            parts.append(classrooms[0])
        if teacher:
            parts.append(teacher)
        lines.append(" ".join(p for p in parts if p))
        return lines

    for idx, (day, slot_start, slot_end, parity) in enumerate(segments):
        if not base_weeks:
            weeks = []
        elif parity == "单":
            weeks = [w for w in base_weeks if w % 2 == 1]
        elif parity == "双":
            weeks = [w for w in base_weeks if w % 2 == 0]
        else:
            weeks = base_weeks

        weeks_str = weeks_to_dsl(weeks)
        slot_repr = f"{slot_start}-{slot_end}" if slot_start != slot_end else str(slot_start)
        room = classrooms[idx] if idx < len(classrooms) else (classrooms[0] if classrooms else "")

        tokens = [name, "@", str(day), slot_repr]
        if weeks_str:
            tokens.append(weeks_str)
        if room:
            tokens.append(room)
        if teacher:
            tokens.append(teacher)
        lines.append(" ".join(tokens))
    return lines


def to_dsl(courses: List[Dict[str, str]]) -> str:
    """全部课程 -> DSL 文本（带注释头）"""
    header = [
        "# 课表 DSL - 从 SICAU 教务系统自动抓取",
        "# 格式: 课程名 @ 星期(1-7) 节次 [w周次] [位置] [教师]",
        "# 抓取时间: " + __import__("datetime").datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "",
    ]
    body: List[str] = []
    for c in courses:
        body.extend(course_to_dsl_lines(c))
    return "\n".join(header + body) + "\n"


# ----------------------------- 主流程 -----------------------------

def main() -> int:
    p = argparse.ArgumentParser(description="SICAU 教务系统课表抓取 → DSL")
    p.add_argument("--user", required=True, help="学号/工号")
    p.add_argument("--password", required=True, help="密码")
    p.add_argument("--semester", default=DEFAULT_SEMESTER, help="学期，如 2025-2026-2")
    p.add_argument("--output", "-o", default="timetable.dsl", help="DSL 输出文件路径")
    p.add_argument("--json-output", default=None, help="可选，结构化 JSON 输出路径")
    args = p.parse_args()

    session = requests.Session()

    print(f"[1/4] 登录 SICAU 教务系统 ... user={args.user}")
    login(session, args.user, args.password)
    print("      登录成功 ✓")

    print(f"[2/4] 切到学期 {args.semester} 并拉取课表 HTML ...")
    html = fetch_timetable_html(session, args.semester)
    print(f"      HTML 大小 {len(html)} 字节")

    print("[3/4] 解析课表 ...")
    courses = parse_courses(html)
    print(f"      解析到 {len(courses)} 门课程")

    dsl = to_dsl(courses)
    with open(args.output, "w", encoding="utf-8") as f:
        f.write(dsl)
    print(f"[4/4] DSL 已写入 {args.output} ✓")

    if args.json_output:
        with open(args.json_output, "w", encoding="utf-8") as f:
            json.dump(courses, f, ensure_ascii=False, indent=2)
        print(f"      JSON 已写入 {args.json_output} ✓")

    # 打印前 3 行 DSL 预览
    preview = dsl.splitlines()
    print("\n----- DSL 预览（前 5 行课程）-----")
    for line in [l for l in preview if l and not l.startswith("#")][:5]:
        print(line)
    print("-----------------------------")
    return 0


if __name__ == "__main__":
    sys.exit(main())
