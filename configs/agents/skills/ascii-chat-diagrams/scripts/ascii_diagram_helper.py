#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ASCII chat diagram alignment helper (ascii-chat-diagrams)

Features:
- High-Speed Monospace Column Width Engine (CJK Wide 2ch, Nerd Font 1ch, ASCII 1ch, Box 1ch, Ambiguous 2ch)
- 1-Shot AutoFit: Forces any rough TUI draft to exactly target width W with zero overflow
- Multi-Column Split Alignment: Automatically detects internal '│' and maintains collinear vertical dividers
- Interactive Component Generators: Sliders, Progress Bars, Framed Cards, Multi-pane Grids
- 100% Deterministic Validation
"""

import sys
import re
import unicodedata
import argparse
from typing import List, Tuple, Optional

CANVAS_WIDTHS = {
    "pc": 80,
    "tablet": 56,
    "sp": 32,
    "mobile": 32,
    "flow": 120,
    "inline": 48,
}

def inner_content_width(target_w: int, num_cols: int) -> int:
    """Total monospace width available for column content (excludes outer │ and internal dividers)."""
    return target_w - 2 - max(0, num_cols - 1)

def normalize_col_widths(col_widths: List[int], target_w: int) -> List[int]:
    """Adjust column widths so content + dividers + outer borders equals target_w exactly."""
    if not col_widths:
        return col_widths
    n = len(col_widths)
    avail = inner_content_width(target_w, n)
    total = sum(col_widths)
    if total == avail:
        return col_widths
    widths = list(col_widths)
    widths[-1] += avail - total
    if widths[-1] < 1:
        base = max(1, avail // n)
        widths = [base] * n
        widths[-1] += avail - sum(widths)
    return widths

def infer_col_widths(num_cols: int, target_w: int) -> List[int]:
    """Split inner width across n columns; 2-column layouts bias narrow left (nav/sidebar)."""
    if num_cols < 1:
        return []
    avail = inner_content_width(target_w, num_cols)
    if avail < num_cols:
        return [max(1, avail // num_cols)] * num_cols
    if num_cols == 2:
        first = min(22, max(1, avail // 3))
        second = avail - first
        if second < 1:
            first = avail // 2
            second = avail - first
        return [first, second]
    base = avail // num_cols
    widths = [base] * num_cols
    widths[-1] += avail - sum(widths)
    return widths

def is_horizontal_rule(content: str) -> bool:
    """True when line is a plain horizontal rule (only dash/box chars)."""
    stripped = content.strip()
    return bool(stripped) and all(c in "─━═-" for c in stripped)

def detect_column_count(lines: List[str]) -> int:
    """Detect max column count from multi-column borders or content rows."""
    max_cols = 1
    for line in lines:
        s = strip_bom(line.rstrip("\r\n"))
        if not s:
            continue
        if s[0] in "┌└├╭╰" and "┬" in s:
            return s[1:-1].count("┬") + 1
        inner = s
        if inner.startswith("│"):
            inner = inner[1:]
        if inner.endswith("│"):
            inner = inner[:-1]
        if "│" in inner:
            max_cols = max(max_cols, len(inner.split("│")))
    return max_cols

def parse_split(raw: str) -> List[int]:
    """Parse comma-separated column widths; exit 2 on invalid input."""
    parts = [x.strip() for x in raw.split(",") if x.strip()]
    if not parts:
        print("Error: --split requires at least one integer width.", file=sys.stderr)
        sys.exit(2)
    out: List[int] = []
    for part in parts:
        try:
            out.append(int(part))
        except ValueError:
            print(f"Error: invalid column width in --split: {part!r}", file=sys.stderr)
            sys.exit(2)
    return out

def shrink_title_tag(title: str, target_w: int, ambiguous_as_wide: bool = True) -> str:
    """Truncate title so a titled top border fits within target_w."""
    t = title
    tag = f"[ {t} ]"
    prefix = f"┌─ {tag} "
    while t and get_line_width(prefix, ambiguous_as_wide) >= target_w - 1:
        t = truncate_to_width(t, max(1, get_line_width(t, ambiguous_as_wide) - 1), ellipsis="...", ambiguous_as_wide=ambiguous_as_wide)
        tag = f"[ {t} ]"
        prefix = f"┌─ {tag} "
    return tag

def parse_float_list(raw: str, label: str) -> List[float]:
    """Parse comma-separated floats; exit 2 with message on invalid input."""
    items = [x.strip() for x in raw.split(",") if x.strip()]
    if not items:
        print(f"Error: {label} requires at least one numeric value.", file=sys.stderr)
        sys.exit(2)
    out: List[float] = []
    for item in items:
        try:
            out.append(float(item))
        except ValueError:
            print(f"Error: invalid number in {label}: {item!r}", file=sys.stderr)
            sys.exit(2)
    return out

def emit_diagram(lines: List[str], target_w: int, command: str) -> None:
    """Print diagram lines; exit 1 if alignment validation fails."""
    is_valid, report = validate_diagram(lines, target_w)
    for line in lines:
        print(line)
    if is_valid:
        return
    for r in report:
        if "[OK]" not in r:
            print(r, file=sys.stderr)
    print(f"\n[FAIL] {command} produced misaligned output (expected W={target_w}).", file=sys.stderr)
    sys.exit(1)

def get_char_width(c: str, ambiguous_as_wide: bool = True) -> int:
    """Returns visual monospace column width in Japanese / modern terminal environments."""
    code = ord(c)
    # Nerd Font Private Use Area (PUA) -> 1 ch
    if (0xE000 <= code <= 0xF8FF) or (0xF0000 <= code <= 0xFFFFD) or (0x100000 <= code <= 0x10FFFD):
        return 1
    # Unicode Box Drawing (2500-257F) & Block Elements (2580-259F) -> 1 ch
    if 0x2500 <= code <= 0x259F:
        return 1
    # Standard ASCII printable -> 1 ch
    if 0x20 <= code <= 0x7E:
        return 1
    # CJK Wide & Fullwidth -> 2 ch
    eaw = unicodedata.east_asian_width(c)
    if eaw in ('F', 'W'):
        return 2
    # East Asian Ambiguous (※, …, ★, ▲, ◆, 　) -> 2 ch in CJK / NF fonts
    if ambiguous_as_wide and eaw == 'A':
        return 2
    # Emojis & Pictographs -> 2 ch
    if 0x1F300 <= code <= 0x1FAFF:
        return 2
    # Narrow / Halfwidth Katakana -> 1 ch
    return 1

def get_line_width(line: str, ambiguous_as_wide: bool = True) -> int:
    """Calculates the total visual monospace column width of a line."""
    return sum(get_char_width(c, ambiguous_as_wide) for c in line)

def truncate_to_width(text: str, max_w: int, ellipsis: str = "...", ambiguous_as_wide: bool = True) -> str:
    """Safely truncates text to fit within max_w columns, padding if an odd character gap occurs."""
    if get_line_width(text, ambiguous_as_wide) <= max_w:
        return text
    ell_w = get_line_width(ellipsis, ambiguous_as_wide)
    if max_w < ell_w:
        return text[:max_w]
    target = max(0, max_w - ell_w)
    res = []
    curr_w = 0
    for c in text:
        cw = get_char_width(c, ambiguous_as_wide)
        if curr_w + cw > target:
            break
        res.append(c)
        curr_w += cw
    pad = " " * (target - curr_w)
    return "".join(res) + pad + ellipsis

def generate_horizontal_border(target_width: int, left_corner: str = "┌", fill: str = "─", right_corner: str = "┐") -> str:
    """Generates an exact horizontal border line."""
    corner_w = get_line_width(left_corner) + get_line_width(right_corner)
    fill_count = target_width - corner_w
    return f"{left_corner}{fill * max(0, fill_count)}{right_corner}"

def generate_slider(current_val: float, min_val: float, max_val: float, total_width: int, left_label: str = "", right_label: str = "", handle: str = "●", track: str = "─") -> str:
    """Generates an exact-width slider line."""
    l_tag = f" {left_label} " if left_label else " "
    r_tag = f" {right_label} " if right_label else " "
    l_w = get_line_width(l_tag)
    r_w = get_line_width(r_tag)
    h_w = get_line_width(handle)
    
    track_avail = total_width - l_w - r_w - h_w
    if track_avail <= 0:
        return truncate_to_width(f"{left_label} [{handle}] {right_label}", total_width)
    
    ratio = max(0.0, min(1.0, (current_val - min_val) / (max_val - min_val) if max_val > min_val else 0.0))
    left_track_len = int(round(track_avail * ratio))
    right_track_len = track_avail - left_track_len
    
    slider_str = f"{l_tag}{track * left_track_len}{handle}{track * right_track_len}{r_tag}"
    curr_w = get_line_width(slider_str)
    if curr_w < total_width:
        slider_str += " " * (total_width - curr_w)
    elif curr_w > total_width:
        slider_str = truncate_to_width(slider_str, total_width)
    return slider_str

def strip_bom(line: str) -> str:
    """Remove UTF-8 BOM if present (common when drafts are written from PowerShell)."""
    return line.lstrip("\ufeff")

def normalize_lines(lines: List[str]) -> List[str]:
    """Preserve intentional blank rows as empty strings."""
    result: List[str] = []
    for line in lines:
        line = strip_bom(line.rstrip("\r\n"))
        result.append("" if not line.strip() else line)
    return result

def format_inner_content(content: str, avail: int, ambiguous_as_wide: bool = True) -> str:
    """Pad raw inner text with a leading space convention inside │ borders."""
    text = content.rstrip()
    if text and not text.startswith(" ") and text[0] not in "┌└├┤┬┴┼─":
        text = " " + text
    text_w = get_line_width(text, ambiguous_as_wide)
    if text_w > avail:
        text = truncate_to_width(text, avail, ambiguous_as_wide=ambiguous_as_wide)
        text_w = get_line_width(text, ambiguous_as_wide)
    return text + (" " * (avail - text_w))

def is_framed_at_width(lines: List[str], target_w: int, ambiguous_as_wide: bool = True) -> bool:
    """True when input is already a complete box at target width."""
    if len(lines) < 2:
        return False
    if not lines[0].startswith(("┌", "╭")) or not lines[-1].startswith(("└", "╰")):
        return False
    return all(get_line_width(line, ambiguous_as_wide) == target_w for line in lines)

def generate_bar_chart(labels: List[str], values: List[float], total_width: int, fill_char: str = "█", empty_char: str = "░") -> List[str]:
    """Generate labeled horizontal bar chart rows, each exactly total_width columns."""
    if not labels or not values or len(labels) != len(values):
        return []
    max_val = max(values) if max(values) > 0 else 1.0
    label_w = max(get_line_width(lbl) for lbl in labels)
    label_w = min(label_w, max(4, total_width // 3))
    rows = []
    for lbl, val in zip(labels, values):
        prefix = f"{truncate_to_width(lbl, label_w)} "
        prefix_w = get_line_width(prefix)
        bar_area = total_width - prefix_w
        if bar_area < 4:
            rows.append(truncate_to_width(f"{lbl} {fill_char}", total_width))
            continue
        ratio = max(0.0, min(1.0, val / max_val))
        filled = max(1 if val > 0 else 0, int(round((bar_area - 1) * ratio)))
        empty = bar_area - filled
        row = f"{prefix}{fill_char * filled}{empty_char * empty}"
        row_w = get_line_width(row)
        if row_w < total_width:
            row += " " * (total_width - row_w)
        elif row_w > total_width:
            row = truncate_to_width(row, total_width)
        rows.append(row)
    return rows

SPARK_CHARS = "▁▂▃▄▅▆▇█"

def generate_sparkline(values: List[float], total_width: int) -> str:
    """Render a compact sparkline using Unicode block steps."""
    if not values or total_width < 1:
        return ""
    if len(values) > total_width:
        # bucket values to fit width
        bucket_size = len(values) / total_width
        buckets = []
        for i in range(total_width):
            start = int(i * bucket_size)
            end = max(start + 1, int((i + 1) * bucket_size))
            buckets.append(sum(values[start:end]) / (end - start))
        values = buckets
    lo, hi = min(values), max(values)
    span = hi - lo if hi > lo else 1.0
    chars = []
    for v in values:
        idx = int(round((v - lo) / span * (len(SPARK_CHARS) - 1)))
        chars.append(SPARK_CHARS[max(0, min(len(SPARK_CHARS) - 1, idx))])
    line = "".join(chars)
    if len(line) < total_width:
        line += " " * (total_width - len(line))
    elif len(line) > total_width:
        line = line[:total_width]
    return line

def generate_table(headers: List[str], rows: List[List[str]], total_width: int, ambiguous_as_wide: bool = True) -> List[str]:
    """Render a bordered comparison table at exact total_width."""
    if not headers:
        return []
    n = len(headers)
    col_widths = [get_line_width(headers[i], ambiguous_as_wide) + 2 for i in range(n)]
    for row in rows:
        for i in range(n):
            cell = row[i] if i < len(row) else ""
            col_widths[i] = max(col_widths[i], get_line_width(cell, ambiguous_as_wide) + 2, 4)
    avail = total_width - 2 - (n - 1)
    extra = avail - sum(col_widths)
    col_widths[-1] += extra
    if col_widths[-1] < 4:
        col_widths[-1] = 4

    def row_line(cells: List[str]) -> str:
        parts = []
        for i in range(n):
            cell = cells[i] if i < len(cells) else ""
            inner = f" {cell} "
            if get_line_width(inner, ambiguous_as_wide) > col_widths[i]:
                inner = " " + truncate_to_width(cell, max(1, col_widths[i] - 2), ambiguous_as_wide=ambiguous_as_wide) + " "
            pad = col_widths[i] - get_line_width(inner, ambiguous_as_wide)
            parts.append(f"{inner}{' ' * pad}")
        return autofit_line(f"│{'│'.join(parts)}│", total_width, col_widths=col_widths, ambiguous_as_wide=ambiguous_as_wide)

    top = autofit_border("┌" + "┬".join("─" * w for w in col_widths) + "┐", total_width, col_widths=col_widths, ambiguous_as_wide=ambiguous_as_wide)
    mid = autofit_border("├" + "┼".join("─" * w for w in col_widths) + "┤", total_width, col_widths=col_widths, ambiguous_as_wide=ambiguous_as_wide)
    bot = autofit_border("└" + "┴".join("─" * w for w in col_widths) + "┘", total_width, col_widths=col_widths, ambiguous_as_wide=ambiguous_as_wide)
    out = [top, row_line(headers), mid]
    for row in rows:
        out.append(row_line(row))
    out.append(bot)
    return out

def nest_line_in_frame(line: str, target_w: int, col_widths: Optional[List[int]] = None, ambiguous_as_wide: bool = True) -> str:
    """Fit one inner row inside an outer frame (nested boxes shrink to inner width)."""
    avail = target_w - 2
    s = strip_bom(line.rstrip("\r\n"))
    if not s.strip():
        return f"│{' ' * avail}│"
    body = s[1:-1] if s.startswith("│") and s.endswith("│") else s
    body = body.rstrip()
    if is_horizontal_rule(body.strip()):
        return f"│{'─' * avail}│"
    if body.lstrip().startswith(("┌", "└", "├", "╭", "╰")):
        nested = autofit_border(body.lstrip(), avail, col_widths=col_widths, ambiguous_as_wide=ambiguous_as_wide)
        return f"│{nested}│"
    if "│" in body:
        cols = body.split("│")
        widths = col_widths
        if not widths or len(widths) != len(cols):
            widths = infer_col_widths(len(cols), avail + 2)
        else:
            widths = normalize_col_widths(widths, avail + 2)
        parts = []
        for col, cw in zip(cols, widths):
            col_str = col.strip()
            if col.startswith(" "):
                col_str = " " + col_str
            if get_line_width(col_str, ambiguous_as_wide) > cw:
                col_str = truncate_to_width(col_str, cw, ambiguous_as_wide=ambiguous_as_wide)
            parts.append(f"{col_str}{' ' * (cw - get_line_width(col_str, ambiguous_as_wide))}")
        return f"│{'│'.join(parts)}│"
    return f"│{format_inner_content(body.strip(), avail, ambiguous_as_wide)}│"

def frame_diagram(lines: List[str], target_w: int, title: str = "", col_widths: Optional[List[int]] = None, ambiguous_as_wide: bool = True) -> List[str]:
    """Wrap inner content in a titled box at exact target width."""
    inner = [strip_bom(l.rstrip("\r\n")) for l in lines]
    inner = [l for l in inner if l.strip()]
    res: List[str] = []
    if title:
        tag = shrink_title_tag(title, target_w, ambiguous_as_wide)
        res.append(autofit_border(f"┌─ {tag} ─┐", target_w, ambiguous_as_wide=ambiguous_as_wide))
    else:
        res.append(generate_horizontal_border(target_w, "┌", "─", "┐"))
    for line in inner:
        res.append(nest_line_in_frame(line, target_w, col_widths=col_widths, ambiguous_as_wide=ambiguous_as_wide))
    res.append(generate_horizontal_border(target_w, "└", "─", "┘"))
    return res

def generate_progress_bar(val: float, max_val: float, bar_width: int, fill_char: str = "█", empty_char: str = "░") -> str:
    """Generates an exact-width progress bar string e.g. [██████░░░░]."""
    inner_w = bar_width - 2
    if inner_w <= 0:
        return "[]"
    ratio = max(0.0, min(1.0, val / max_val if max_val > 0 else 0.0))
    filled_len = int(round(inner_w * ratio))
    empty_len = inner_w - filled_len
    return f"[{fill_char * filled_len}{empty_char * empty_len}]"

def autofit_border(s: str, target_w: int, col_widths: Optional[List[int]] = None, ambiguous_as_wide: bool = True) -> str:
    """Accurately pads and formats single/multi-titled and multi-column borders to target_w."""
    left_char = s[0]
    right_char = s[-1] if s[-1] in "┐┘┤╮╯" else ("┐" if left_char in "┌╭" else ("┘" if left_char in "└╰" else "┤"))
    inner = s[1:-1]
    
    junctions = [c for c in inner if c in "┬┼┴"]
    if junctions and col_widths:
        widths = normalize_col_widths(col_widths, target_w)
        mid_char = junctions[0]
        parts = ["─" * cw for cw in widths]
        res = f"{left_char}{mid_char.join(parts)}{right_char}"
        cur_w = get_line_width(res, ambiguous_as_wide)
        if cur_w != target_w:
            diff = target_w - cur_w
            if diff > 0:
                res = res[:-1] + ("─" * diff) + right_char
            else:
                res = res[:target_w - 1] + right_char
        return res
        
    tags = re.findall(r'\[.*?\]', inner)
    if tags:
        if len(tags) == 1:
            tag = tags[0]
            tag_w = get_line_width(f"─ {tag} ", ambiguous_as_wide)
            avail = target_w - 2 - tag_w
            fill = "─" * max(0, avail)
            res = f"{left_char}─ {tag} {fill}{right_char}"
        else:
            tag1, tag2 = tags[0], tags[1]
            used = get_line_width(f"─ {tag1} ─ {tag2} ", ambiguous_as_wide)
            avail = target_w - 2 - used
            fill = "─" * max(0, avail)
            res = f"{left_char}─ {tag1} {fill} {tag2} ─{right_char}"
            
        cur_w = get_line_width(res, ambiguous_as_wide)
        if cur_w < target_w:
            res = res[:-1] + ("─" * (target_w - cur_w)) + right_char
        elif cur_w > target_w:
            diff = cur_w - target_w
            res = res.replace("─" * (diff + 1), "─", 1)
        return res
        
    fill = "─" * (target_w - 2)
    return f"{left_char}{fill}{right_char}"

def autofit_line(line: str, target_w: int, col_widths: Optional[List[int]] = None, ambiguous_as_wide: bool = True) -> str:
    """
    Transforms any line of text into a perfectly padded line of exact width target_w.
    Guarantees: get_line_width(result) == target_w without exception.
    """
    s = line.rstrip("\r\n")
    avail = target_w - 2
    
    if not s.strip():
        return f"│{' ' * avail}│"

    # 1. Top/Mid/Bottom Box Borders
    if s[0] in "┌└├╭╰":
        return autofit_border(s, target_w, col_widths=col_widths, ambiguous_as_wide=ambiguous_as_wide)

    # 2. Multi-column content lines with internal '│'
    inner_content = s
    if inner_content.startswith("│"):
        inner_content = inner_content[1:]
    if inner_content.endswith("│"):
        inner_content = inner_content[:-1]
        
    cols = inner_content.split("│")
    if len(cols) > 1:
        if not col_widths or len(col_widths) != len(cols):
            col_widths = infer_col_widths(len(cols), target_w)
        else:
            col_widths = normalize_col_widths(col_widths, target_w)
        padded_cols = []
        for col, cw in zip(cols, col_widths):
            col_str = col.strip()
            if col.startswith(" "):
                col_str = " " + col_str
            if get_line_width(col_str, ambiguous_as_wide) > cw:
                col_str = truncate_to_width(col_str, cw, ambiguous_as_wide=ambiguous_as_wide)
            pad = " " * (cw - get_line_width(col_str, ambiguous_as_wide))
            padded_cols.append(f"{col_str}{pad}")
        return f"│{'│'.join(padded_cols)}│"

    # 3. Single-column content line
    content = inner_content.rstrip()
    if not content:
        return f"│{' ' * avail}│"
    if is_horizontal_rule(content):
        return f"│{'─' * avail}│"
    padded = format_inner_content(content, avail, ambiguous_as_wide)
    return f"│{padded}│"

def autofit_diagram(lines: List[str], target_w: int, col_widths: Optional[List[int]] = None, ambiguous_as_wide: bool = True) -> List[str]:
    """Processes an entire multi-line diagram draft and guarantees exact target width."""
    lines = normalize_lines(lines)
    if is_framed_at_width(lines, target_w, ambiguous_as_wide):
        return [autofit_line(line, target_w, col_widths=col_widths, ambiguous_as_wide=ambiguous_as_wide) for line in lines]

    if col_widths:
        ncols = len(col_widths)
        col_widths = normalize_col_widths(col_widths, target_w)
    else:
        ncols = detect_column_count(lines)
        if ncols > 1:
            col_widths = infer_col_widths(ncols, target_w)

    res = []
    if lines and not lines[0].startswith(("┌", "╭")):
        res.append(generate_horizontal_border(target_w, "┌", "─", "┐"))
        
    for line in lines:
        res.append(autofit_line(line, target_w, col_widths=col_widths, ambiguous_as_wide=ambiguous_as_wide))
        
    if lines and not lines[-1].startswith(("└", "╰")):
        res.append(generate_horizontal_border(target_w, "└", "─", "┘"))
        
    return res

def validate_diagram(lines: List[str], target_width: int, ambiguous_as_wide: bool = True) -> Tuple[bool, List[str]]:
    """Validates that every line strictly equals target_width."""
    is_valid = True
    report = []
    for idx, raw_line in enumerate(lines, start=1):
        line = raw_line.rstrip("\r\n")
        if not line:
            continue
        w = get_line_width(line, ambiguous_as_wide)
        if w != target_width:
            is_valid = False
            diff = w - target_width
            sign = f"+{diff}" if diff > 0 else f"{diff}"
            report.append(f"Line {idx:3d}: width = {w:3d} (expected {target_width}) [{sign} ch] | {line}")
        else:
            report.append(f"Line {idx:3d}: width = {w:3d} [OK]")
    return is_valid, report

def main():
    parser = argparse.ArgumentParser(description="TUI Box Alignment & Declarative Layout Engine")
    parser.add_argument("command", choices=["autofit", "validate", "pad", "frame", "slider", "progress", "barchart", "table", "sparkline", "width"], help="Action")
    parser.add_argument("--title", type=str, default="", help="Title for frame command")
    parser.add_argument("--labels", type=str, default="", help="Comma-separated labels for barchart")
    parser.add_argument("--values", type=str, default="", help="Comma-separated numeric values for barchart/sparkline")
    parser.add_argument("--headers", type=str, default="", help="Comma-separated table headers")
    parser.add_argument("--rows", type=str, default="", help="Pipe-separated table rows; cells comma-separated e.g. a,b|c,d")
    parser.add_argument("--mode", choices=["pc", "tablet", "sp", "mobile", "flow", "inline"], default="pc", help="Canvas mode")
    parser.add_argument("--width", type=int, default=None, help="Explicit target width")
    parser.add_argument("--split", type=str, default=None, help="Comma-separated column widths e.g. 45,32")
    parser.add_argument("--file", "-f", type=str, default=None, help="Input file path")
    parser.add_argument("--text", "-t", type=str, default=None, help="Direct input string")
    parser.add_argument("--val", type=float, default=50.0, help="Value for slider/progress")
    parser.add_argument("--min", type=float, default=0.0, help="Min value for slider")
    parser.add_argument("--max", type=float, default=100.0, help="Max value for slider/progress")
    parser.add_argument("--label-left", type=str, default="", help="Left label for slider")
    parser.add_argument("--label-right", type=str, default="", help="Right label for slider")
    parser.add_argument("--strict-western", action="store_true", help="Treat Ambiguous as 1ch (Western fonts)")

    args = parser.parse_args()
    ambiguous_as_wide = not args.strict_western
    target_w = args.width if args.width is not None else CANVAS_WIDTHS.get(args.mode, 80)
    col_widths = parse_split(args.split) if args.split else None

    if args.command == "slider":
        s = generate_slider(args.val, args.min, args.max, target_w, args.label_left, args.label_right)
        emit_diagram([s], target_w, "slider")
        sys.exit(0)

    if args.command == "progress":
        p = generate_progress_bar(args.val, args.max, target_w)
        emit_diagram([p], target_w, "progress")
        sys.exit(0)

    if args.command == "barchart":
        labels = [x.strip() for x in args.labels.split(",") if x.strip()]
        if not labels:
            print("Error: barchart requires --labels.", file=sys.stderr)
            sys.exit(2)
        values = parse_float_list(args.values, "--values")
        if len(labels) != len(values):
            print(f"Error: labels count ({len(labels)}) must match values count ({len(values)}).", file=sys.stderr)
            sys.exit(2)
        rows = generate_bar_chart(labels, values, target_w)
        if not rows:
            print("Error: barchart produced no output.", file=sys.stderr)
            sys.exit(2)
        emit_diagram(rows, target_w, "barchart")
        sys.exit(0)

    if args.command == "sparkline":
        values = parse_float_list(args.values, "--values")
        line = generate_sparkline(values, target_w)
        if not line:
            print("Error: sparkline produced no output.", file=sys.stderr)
            sys.exit(2)
        emit_diagram([line], target_w, "sparkline")
        sys.exit(0)

    if args.command == "table":
        headers = [x.strip() for x in args.headers.split(",") if x.strip()]
        if not headers:
            print("Error: table requires --headers.", file=sys.stderr)
            sys.exit(2)
        rows = []
        if args.rows.strip():
            for row in args.rows.split("|"):
                cells = [c.strip() for c in row.split(",")]
                if len(cells) != len(headers):
                    print(f"Error: row {cells!r} has {len(cells)} cells, expected {len(headers)}.", file=sys.stderr)
                    sys.exit(2)
                rows.append(cells)
        table_lines = generate_table(headers, rows, target_w, ambiguous_as_wide=ambiguous_as_wide)
        emit_diagram(table_lines, target_w, "table")
        sys.exit(0)

    lines = []
    if args.text is not None:
        lines = args.text.splitlines()
    elif args.file is not None:
        with open(args.file, "r", encoding="utf-8") as f:
            lines = f.read().splitlines()
    elif not sys.stdin.isatty():
        lines = sys.stdin.read().splitlines()
    else:
        print("Error: No input provided. Use --file, --text, or pipe via stdin.", file=sys.stderr)
        sys.exit(1)

    if args.command == "autofit":
        fitted = autofit_diagram(lines, target_w, col_widths=col_widths, ambiguous_as_wide=ambiguous_as_wide)
        emit_diagram(fitted, target_w, "autofit")
        sys.exit(0)

    if args.command == "validate":
        is_valid, report = validate_diagram(lines, target_w, ambiguous_as_wide)
        for r in report:
            print(r)
        if is_valid:
            print(f"\n[PASS] All {len(lines)} lines perfectly match target width W={target_w} ch.")
            sys.exit(0)
        else:
            print(f"\n[FAIL] Alignment errors detected against target width W={target_w} ch.", file=sys.stderr)
            sys.exit(1)

    if args.command == "pad":
        padded = [autofit_line(line, target_w, col_widths=col_widths, ambiguous_as_wide=ambiguous_as_wide) for line in normalize_lines(lines)]
        emit_diagram(padded, target_w, "pad")
        sys.exit(0)

    if args.command == "frame":
        framed = frame_diagram(lines, target_w, title=args.title, col_widths=col_widths, ambiguous_as_wide=ambiguous_as_wide)
        emit_diagram(framed, target_w, "frame")
        sys.exit(0)

    if args.command == "width":
        for idx, line in enumerate(lines, start=1):
            w = get_line_width(line, ambiguous_as_wide)
            print(f"Line {idx:3d} (w={w:3d}): {line}")

if __name__ == "__main__":
    main()
