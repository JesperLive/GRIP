#!/usr/bin/env python3
r"""
cowork_util.py -- Reusable Cowork-lane utility for GRIP projects.

Replaces throwaway %TEMP% scripts. Handles all the common patterns that
PowerShell mangles when passed as DC one-liners (f-strings, brackets, quotes).

Usage (from DC start_process, always via cmd /c to avoid PS mangling):

  cmd /c "cd /d C:\Users\dries\Documents\GRIP && python Tools\cowork_util.py <command> [args]"

Commands:
  lines <file> <start> <end>          Show lines start-end from a file
  search <pattern> <glob> [--context N]  Grep for pattern in files matching glob
  luacheck [--summary] [--category CAT]  Run luacheck and parse/categorize output
  count <file> <pattern>              Count occurrences of pattern in file
  diff <file1> <file2>                Side-by-side diff of two files
  upvalues <file>                     Show upvalue block and flag unused ones
  head <file> [N]                     Show first N lines (default 40)
  tail <file> [N]                     Show last N lines (default 40)

Author: MrSataana (GRIP project)
"""
import sys
import os
import re
import subprocess
import argparse
from pathlib import Path
from collections import defaultdict

sys.stdout.reconfigure(encoding='utf-8')

REPO_ROOT = Path(__file__).resolve().parent.parent
RESULT_FILE = os.path.join(os.environ.get('TEMP', '/tmp'), 'grip_cowork_result.txt')


def _write_result(lines):
    """Write output to result file AND stdout. DC pipe truncates fast stdout,
    so Cowork reads the result file via read_multiple_files as fallback."""
    text = '\n'.join(lines)
    with open(RESULT_FILE, 'w', encoding='utf-8') as f:
        f.write(text + '\n')
    print(text)
    sys.stdout.flush()
    # Print path hint so Cowork knows where to read if truncated
    print("\n[Result: %s]" % RESULT_FILE)
    sys.stdout.flush()


def cmd_lines(args):
    """Show lines start-end from a file."""
    fpath = REPO_ROOT / args.file if not os.path.isabs(args.file) else Path(args.file)
    with open(fpath, encoding='utf-8', errors='replace') as f:
        all_lines = f.readlines()
    start = max(1, args.start)
    end = min(len(all_lines), args.end)
    print("--- %s [%d-%d of %d] ---" % (args.file, start, end, len(all_lines)))
    for i in range(start - 1, end):
        print("%4d: %s" % (i + 1, all_lines[i].rstrip()))


def cmd_search(args):
    """Grep for pattern in files matching glob."""
    import fnmatch
    pattern = re.compile(args.pattern, re.IGNORECASE if args.ignore_case else 0)
    ctx = args.context or 0
    matches = 0
    for root, dirs, files in os.walk(REPO_ROOT):
        # Skip excluded dirs
        dirs[:] = [d for d in dirs if d not in ('Libs', '.git', '__pycache__', 'Tools')]
        rel_root = os.path.relpath(root, REPO_ROOT)
        for fname in files:
            if not fnmatch.fnmatch(fname, args.glob):
                continue
            fpath = os.path.join(root, fname)
            rel_path = os.path.join(rel_root, fname) if rel_root != '.' else fname
            try:
                with open(fpath, encoding='utf-8', errors='replace') as f:
                    lines = f.readlines()
            except Exception:
                continue
            for i, line in enumerate(lines):
                if pattern.search(line):
                    matches += 1
                    print("--- %s:%d ---" % (rel_path, i + 1))
                    start = max(0, i - ctx)
                    end = min(len(lines), i + ctx + 1)
                    for j in range(start, end):
                        marker = ">>>" if j == i else "   "
                        print("%s %4d: %s" % (marker, j + 1, lines[j].rstrip()))
    if matches == 0:
        print("No matches for /%s/ in %s" % (args.pattern, args.glob))
    else:
        print("\n%d match(es) found." % matches)


def cmd_luacheck(args):
    """Run luacheck and parse/categorize output."""
    # Run luacheck, capture to temp file first (DC stdout pipe can miss fast output)
    import tempfile
    tmp = os.path.join(tempfile.gettempdir(), 'grip_luacheck_out.txt')
    subprocess.run(
        'luacheck . --no-color > "%s" 2>&1' % tmp,
        shell=True, cwd=str(REPO_ROOT),
    )
    with open(tmp, encoding='utf-8', errors='replace') as f:
        output = f.read()

    if args.raw:
        print(output)
        sys.stdout.flush()
        return

    # Parse warnings into structured data
    warnings = []
    current_file = None
    for line in output.splitlines():
        file_match = re.match(r'^Checking (\S+)', line.strip())
        if file_match:
            current_file = file_match.group(1)
            continue
        warn_match = re.match(r'\s+(\S+):(\d+):(\d+): (.+)', line)
        if warn_match:
            fpath, lineno, col, msg = warn_match.groups()
            # Extract warning code (W### pattern)
            code = ''
            if 'unused variable' in msg or 'unused argument' in msg:
                code = 'W211'
            elif 'line is too long' in msg:
                code = 'W631'
            elif 'empty if branch' in msg:
                code = 'W542'
            elif 'value assigned' in msg and 'unused' in msg:
                code = 'W311'
            elif 'value assigned' in msg and 'overwritten' in msg:
                code = 'W312'
            elif 'unused' in msg:
                code = 'W211'
            else:
                code = 'other'
            warnings.append({
                'file': fpath, 'line': int(lineno), 'col': int(col),
                'msg': msg, 'code': code,
            })

    # Build all output lines, write to result file (DC pipe truncates fast output)
    out = []

    # Summary line from luacheck
    total_line = [l for l in output.splitlines() if l.startswith('Total:')]
    if total_line:
        out.append(total_line[0])
        out.append('')

    if args.summary:
        by_code = defaultdict(list)
        for w in warnings:
            by_code[w['code']].append(w)
        out.append("CATEGORY BREAKDOWN:")
        for code in sorted(by_code.keys()):
            items = by_code[code]
            out.append("  %s: %d warnings" % (code, len(items)))
            by_file = defaultdict(list)
            for w in items:
                by_file[w['file']].append(w)
            for fpath in sorted(by_file.keys()):
                fwarns = by_file[fpath]
                out.append("    %s (%d)" % (fpath, len(fwarns)))

    elif args.category:
        filtered = [w for w in warnings if w['code'] == args.category]
        if not filtered:
            out.append("No warnings with code %s" % args.category)
        else:
            out.append("%s WARNINGS (%d):" % (args.category, len(filtered)))
            for w in filtered:
                out.append("  %s:%d:%d: %s" % (w['file'], w['line'], w['col'], w['msg']))

    else:
        # Default: show all grouped by file
        by_file = defaultdict(list)
        for w in warnings:
            by_file[w['file']].append(w)
        for fpath in sorted(by_file.keys()):
            fwarns = by_file[fpath]
            out.append("%s (%d):" % (fpath, len(fwarns)))
            for w in fwarns:
                out.append("  L%d [%s]: %s" % (w['line'], w['code'], w['msg']))

    _write_result(out)


def cmd_upvalues(args):
    """Show upvalue block from a Lua file and flag unused ones."""
    fpath = REPO_ROOT / args.file if not os.path.isabs(args.file) else Path(args.file)
    with open(fpath, encoding='utf-8', errors='replace') as f:
        all_lines = f.readlines()

    # Find upvalue block (local X = X pattern in first 30 lines)
    upvalue_lines = []
    body_start = 0
    for i, line in enumerate(all_lines[:30]):
        stripped = line.strip()
        if re.match(r'^local\s+\w+.*=\s+(string\.|math\.|table\.|pairs|ipairs|type|'
                     r'tostring|tonumber|select|next|pcall|wipe|strsplit|format|'
                     r'date|time|random|hooksecurefunc|tinsert|tremove|'
                     r'GetTime|GetGuildInfo|InCombatLockdown|IsInGuild|'
                     r'CanGuildInvite|GetNormalizedRealmName|GetRealZoneText|'
                     r'CreateFrame|CreateColor)', stripped):
            upvalue_lines.append((i, stripped))
            body_start = i + 1
        elif upvalue_lines and not stripped:
            body_start = i + 1
            break
        elif upvalue_lines and not stripped.startswith('local'):
            break

    if not upvalue_lines:
        print("No upvalue block found in first 30 lines of %s" % args.file)
        return

    # Get body text (everything after upvalue block)
    body = ''.join(all_lines[body_start:])

    print("UPVALUE BLOCK in %s (body starts at line %d):" % (args.file, body_start + 1))
    for lineno, content in upvalue_lines:
        # Extract variable names from the assignment
        lhs = content.split('=')[0].replace('local', '').strip()
        var_names = [v.strip() for v in lhs.split(',')]
        status_parts = []
        for var in var_names:
            # Search for usage in body (word boundary match)
            pattern = r'\b' + re.escape(var) + r'\b'
            used = bool(re.search(pattern, body))
            status_parts.append('%s:%s' % (var, 'USED' if used else 'UNUSED'))
        print("  L%d: %s" % (lineno + 1, '  '.join(status_parts)))


def cmd_count(args):
    """Count occurrences of pattern in a file."""
    fpath = REPO_ROOT / args.file if not os.path.isabs(args.file) else Path(args.file)
    pattern = re.compile(args.pattern)
    with open(fpath, encoding='utf-8', errors='replace') as f:
        content = f.read()
    matches = pattern.findall(content)
    print("%d occurrence(s) of /%s/ in %s" % (len(matches), args.pattern, args.file))


def cmd_diff(args):
    """Simple line-by-line diff of two files."""
    import difflib
    fpath1 = REPO_ROOT / args.file1 if not os.path.isabs(args.file1) else Path(args.file1)
    fpath2 = REPO_ROOT / args.file2 if not os.path.isabs(args.file2) else Path(args.file2)
    with open(fpath1, encoding='utf-8', errors='replace') as f:
        lines1 = f.readlines()
    with open(fpath2, encoding='utf-8', errors='replace') as f:
        lines2 = f.readlines()
    diff = difflib.unified_diff(lines1, lines2,
                                 fromfile=str(args.file1), tofile=str(args.file2),
                                 lineterm='')
    output = list(diff)
    if not output:
        print("Files are identical.")
    else:
        for line in output:
            print(line)


def cmd_head(args):
    """Show first N lines of a file."""
    n = args.n or 40
    fpath = REPO_ROOT / args.file if not os.path.isabs(args.file) else Path(args.file)
    with open(fpath, encoding='utf-8', errors='replace') as f:
        all_lines = f.readlines()
    end = min(n, len(all_lines))
    print("--- %s [1-%d of %d] ---" % (args.file, end, len(all_lines)))
    for i in range(end):
        print("%4d: %s" % (i + 1, all_lines[i].rstrip()))


def cmd_tail(args):
    """Show last N lines of a file."""
    n = args.n or 40
    fpath = REPO_ROOT / args.file if not os.path.isabs(args.file) else Path(args.file)
    with open(fpath, encoding='utf-8', errors='replace') as f:
        all_lines = f.readlines()
    start = max(0, len(all_lines) - n)
    print("--- %s [%d-%d of %d] ---" % (args.file, start + 1, len(all_lines), len(all_lines)))
    for i in range(start, len(all_lines)):
        print("%4d: %s" % (i + 1, all_lines[i].rstrip()))


def main():
    parser = argparse.ArgumentParser(
        description="GRIP Cowork-lane utility -- replaces throwaway temp scripts",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest='command', help='Available commands')

    # lines
    p = sub.add_parser('lines', help='Show lines start-end from a file')
    p.add_argument('file', help='File path (relative to repo root or absolute)')
    p.add_argument('start', type=int, help='Start line number')
    p.add_argument('end', type=int, help='End line number')

    # search
    p = sub.add_parser('search', help='Grep for pattern in files matching glob')
    p.add_argument('pattern', help='Regex pattern to search for')
    p.add_argument('glob', help='File glob pattern (e.g. *.lua)')
    p.add_argument('--context', '-C', type=int, default=0, help='Context lines')
    p.add_argument('--ignore-case', '-i', action='store_true')

    # luacheck
    p = sub.add_parser('luacheck', help='Run and parse luacheck output')
    p.add_argument('--summary', '-s', action='store_true', help='Category breakdown')
    p.add_argument('--category', '-c', help='Filter by category (W211, W631, etc.)')
    p.add_argument('--raw', '-r', action='store_true', help='Show raw luacheck output')

    # count
    p = sub.add_parser('count', help='Count pattern occurrences in a file')
    p.add_argument('file', help='File path')
    p.add_argument('pattern', help='Regex pattern')

    # diff
    p = sub.add_parser('diff', help='Diff two files')
    p.add_argument('file1', help='First file')
    p.add_argument('file2', help='Second file')

    # upvalues
    p = sub.add_parser('upvalues', help='Analyze upvalue block in a Lua file')
    p.add_argument('file', help='Lua file path')

    # head
    p = sub.add_parser('head', help='Show first N lines')
    p.add_argument('file', help='File path')
    p.add_argument('n', type=int, nargs='?', default=40, help='Number of lines')

    # tail
    p = sub.add_parser('tail', help='Show last N lines')
    p.add_argument('file', help='File path')
    p.add_argument('n', type=int, nargs='?', default=40, help='Number of lines')

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    dispatch = {
        'lines': cmd_lines,
        'search': cmd_search,
        'luacheck': cmd_luacheck,
        'count': cmd_count,
        'diff': cmd_diff,
        'upvalues': cmd_upvalues,
        'head': cmd_head,
        'tail': cmd_tail,
    }
    dispatch[args.command](args)


if __name__ == '__main__':
    main()
