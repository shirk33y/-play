#!/usr/bin/env python3
r"""Tiny static Lua string escape checker.
Catches regressions like ASS strings written as '{\an7\pos...}', where \p is an invalid Lua escape.
This is not a full Lua parser; it is a conservative guard for single/double quoted strings.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
files = sorted((ROOT / 'mpv/scripts').glob('*.lua'))
allowed_simple = set('abfnrtv\\\"\'\n')


def fail(path, line, col, msg):
    raise SystemExit(f'{path}:{line}:{col}: {msg}')


def check_file(path: Path):
    text = path.read_text()
    i = 0
    line = 1
    col = 1
    n = len(text)
    while i < n:
        ch = text[i]
        # skip comments, including long comments --[[...]] / --[=[...]=]
        if ch == '-' and i + 1 < n and text[i+1] == '-':
            j = i + 2
            if j < n and text[j] == '[':
                k = j + 1
                eq = 0
                while k < n and text[k] == '=':
                    eq += 1; k += 1
                if k < n and text[k] == '[':
                    end = ']' + ('=' * eq) + ']'
                    k += 1
                    endpos = text.find(end, k)
                    seg = text[i:n if endpos < 0 else endpos + len(end)]
                    line += seg.count('\n')
                    if '\n' in seg:
                        col = len(seg.rsplit('\n', 1)[-1]) + 1
                    else:
                        col += len(seg)
                    i += len(seg)
                    continue
            while i < n and text[i] != '\n':
                i += 1; col += 1
            continue
        # skip long strings [[...]] / [=[...]=]
        if ch == '[':
            k = i + 1
            eq = 0
            while k < n and text[k] == '=':
                eq += 1; k += 1
            if k < n and text[k] == '[':
                end = ']' + ('=' * eq) + ']'
                endpos = text.find(end, k + 1)
                seg = text[i:n if endpos < 0 else endpos + len(end)]
                line += seg.count('\n')
                if '\n' in seg:
                    col = len(seg.rsplit('\n', 1)[-1]) + 1
                else:
                    col += len(seg)
                i += len(seg)
                continue
        if ch in ('"', "'"):
            quote = ch
            i += 1; col += 1
            while i < n:
                c = text[i]
                if c == '\n':
                    fail(path, line, col, 'newline inside quoted string')
                if c == quote:
                    i += 1; col += 1
                    break
                if c == '\\':
                    esc_line, esc_col = line, col
                    i += 1; col += 1
                    if i >= n:
                        fail(path, esc_line, esc_col, 'trailing backslash in string')
                    e = text[i]
                    if e in '0123456789':
                        # decimal escape: up to 3 digits
                        count = 0
                        while i < n and text[i].isdigit() and count < 3:
                            i += 1; col += 1; count += 1
                        continue
                    if e == 'x':
                        hx = text[i+1:i+3]
                        if len(hx) != 2 or any(c not in '0123456789abcdefABCDEF' for c in hx):
                            fail(path, esc_line, esc_col, 'bad Lua hex escape')
                        i += 3; col += 3
                        continue
                    if e == 'u':
                        if i + 1 >= n or text[i+1] != '{':
                            fail(path, esc_line, esc_col, 'bad Lua unicode escape')
                        end = text.find('}', i + 2)
                        if end < 0:
                            fail(path, esc_line, esc_col, 'unterminated Lua unicode escape')
                        col += end - i + 1
                        i = end + 1
                        continue
                    if e in allowed_simple or e == 'z':
                        i += 1; col += 1
                        continue
                    fail(path, esc_line, esc_col, f'invalid Lua escape \\{e}')
                else:
                    i += 1; col += 1
            continue
        if ch == '\n':
            line += 1; col = 1; i += 1
        else:
            i += 1; col += 1

for f in files:
    check_file(f)
print(f'Lua static checks OK ({len(files)} files)')
