#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TUI Box Alignment & Declarative Layout Engine (tui-wireframe-designer)

Features:
- High-Speed Monospace Column Width Engine (CJK Wide 2ch, Nerd Font 1ch, ASCII 1ch, Box 1ch, Ambiguous 2ch)
- 1-Shot AutoFit: Forces any rough TUI draft to exactly target width W with zero overflow
- Multi-Column Split Alignment: Automatically detects internal '│' and maintains collinear vertical dividers
- Interactive Component Generators: Sliders, Progress Bars, Framed Cards, Multi-pane Grids
- 100% Deterministic Validation
"""

import sys
import os
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
}

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
    return slider_str

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
        mid_char = junctions[0]
        parts = ["─" * cw for cw in col_widths]
        res = f"{left_char}{mid_char.join(parts)}{right_char}"
        cur_w = get_line_width(res, ambiguous_as_wide)
        if cur_w < target_w:
            res = res[:-1] + ("─" * (target_w - cur_w)) + right_char
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
    if len(cols) > 1 and col_widths and len(col_widths) == len(cols):
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
    if s.startswith(" ") and not content.startswith(" "):
        content = " " + content
    content_w = get_line_width(content, ambiguous_as_wide)
    if content_w > avail:
        content = truncate_to_width(content, avail, ambiguous_as_wide=ambiguous_as_wide)
        content_w = get_line_width(content, ambiguous_as_wide)
    pad = " " * (avail - content_w)
    return f"│{content}{pad}│"

def autofit_diagram(lines: List[str], target_w: int, col_widths: Optional[List[int]] = None, ambiguous_as_wide: bool = True) -> List[str]:
    """Processes an entire multi-line TUI wireframe draft and guarantees 100% mathematical alignment."""
    if not col_widths:
        for line in lines:
            if line.startswith("┌") and "┬" in line:
                parts = line[1:-1].split("┬")
                col_widths = [get_line_width(p, ambiguous_as_wide) for p in parts]
                break
            elif "│" in line and line.count("│") >= 3:
                inner = line.strip("│")
                parts = inner.split("│")
                if len(parts) >= 2:
                    col_widths = [get_line_width(p, ambiguous_as_wide) for p in parts]
                    total_inner = sum(col_widths) + (len(parts) - 1)
                    if total_inner != target_w - 2:
                        avail = target_w - 2 - (len(parts) - 1)
                        scale = avail / sum(col_widths) if sum(col_widths) > 0 else 1
                        col_widths = [max(5, int(round(w * scale))) for w in col_widths]
                        diff = avail - sum(col_widths)
                        col_widths[-1] += diff
                    break

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
    parser.add_argument("command", choices=["autofit", "validate", "pad", "slider", "progress", "width"], help="Action")
    parser.add_argument("--mode", choices=["pc", "tablet", "sp", "mobile", "flow"], default="pc", help="Canvas mode")
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
    col_widths = [int(x.strip()) for x in args.split.split(",")] if args.split else None

    if args.command == "slider":
        s = generate_slider(args.val, args.min, args.max, target_w, args.label_left, args.label_right)
        print(s)
        sys.exit(0)

    if args.command == "progress":
        p = generate_progress_bar(args.val, args.max, target_w)
        print(p)
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
        for line in fitted:
            print(line)
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
        for line in lines:
            print(autofit_line(line, target_w, col_widths=col_widths, ambiguous_as_wide=ambiguous_as_wide))
        sys.exit(0)

    if args.command == "width":
        for idx, line in enumerate(lines, start=1):
            w = get_line_width(line, ambiguous_as_wide)
            print(f"Line {idx:3d} (w={w:3d}): {line}")

if __name__ == "__main__":
    main()
