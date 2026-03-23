#!/usr/bin/env python3
r"""cowork_util.py -- Reusable Cowork-lane utility for GRIP projects.

Commands: lines, search, luacheck, count, diff, upvalues, head, tail, process-intake
Author: MrSataana (GRIP project)
"""
import sys
import os
import re
import subprocess
import argparse
import difflib
from pathlib import Path
from datetime import datetime
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


def _resolve_file_targets(glob_arg):
    """Resolve the glob/file argument into a list of (abs_path, rel_path) tuples.

    If glob_arg contains a path separator (/ or \\) or points to an existing
    file relative to REPO_ROOT, treat it as a specific file path.
    Otherwise, walk the repo tree matching filenames against the glob pattern.
    """
    import fnmatch

    # Check if it looks like a specific file path
    norm = glob_arg.replace('\\', '/')
    candidate = REPO_ROOT / norm
    if os.sep in glob_arg or '/' in glob_arg or candidate.is_file():
        if candidate.is_file():
            return [(str(candidate), norm)]
        else:
            print("File not found: %s (resolved to %s)" % (glob_arg, candidate))
            return []

    # Walk the tree with glob matching on filenames
    targets = []
    for root, dirs, files in os.walk(REPO_ROOT):
        dirs[:] = [d for d in dirs if d not in ('Libs', '.git', '__pycache__', 'Tools')]
        rel_root = os.path.relpath(root, REPO_ROOT)
        for fname in files:
            if not fnmatch.fnmatch(fname, glob_arg):
                continue
            fpath = os.path.join(root, fname)
            rel_path = os.path.join(rel_root, fname) if rel_root != '.' else fname
            targets.append((fpath, rel_path))
    return targets


def cmd_search(args):
    """Grep for pattern in files matching glob or a specific file path.

    Case-INSENSITIVE by default (use -s for case-sensitive).
    Supports OR patterns via comma separator: "pat1,pat2,pat3"
    (avoids CMD pipe-eating issues with regex |).
    """
    # Build regex: replace commas with | for OR matching (CMD-safe alternative)
    raw_pattern = args.pattern.replace(',', '|') if ',' in args.pattern else args.pattern
    flags = 0 if args.case_sensitive else re.IGNORECASE
    pattern = re.compile(raw_pattern, flags)
    ctx = args.context or 0
    matches = 0

    targets = _resolve_file_targets(args.glob)
    if not targets:
        return

    for fpath, rel_path in targets:
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
        print("No matches for /%s/ in %s" % (raw_pattern, args.glob))
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
    fpath1 = REPO_ROOT / args.file1 if not os.path.isabs(args.file1) else Path(args.file1)
    fpath2 = REPO_ROOT / args.file2 if not os.path.isabs(args.file2) else Path(args.file2)
    with open(fpath1, encoding='utf-8', errors='replace') as f:
        lines1 = f.readlines()
    with open(fpath2, encoding='utf-8', errors='replace') as f:
        lines2 = f.readlines()
    output = list(difflib.unified_diff(lines1, lines2,
                  fromfile=str(args.file1), tofile=str(args.file2), lineterm=''))
    if not output: print("Files are identical.")
    else:
        for line in output: print(line)


def _open_file(args_file):
    fpath = REPO_ROOT / args_file if not os.path.isabs(args_file) else Path(args_file)
    with open(fpath, encoding='utf-8', errors='replace') as f:
        return args_file, f.readlines()


def cmd_head(args):
    """Show first N lines of a file."""
    name, lines = _open_file(args.file)
    end = min(args.n or 40, len(lines))
    print("--- %s [1-%d of %d] ---" % (name, end, len(lines)))
    for i in range(end): print("%4d: %s" % (i + 1, lines[i].rstrip()))


def cmd_tail(args):
    """Show last N lines of a file."""
    name, lines = _open_file(args.file)
    start = max(0, len(lines) - (args.n or 40))
    print("--- %s [%d-%d of %d] ---" % (name, start + 1, len(lines), len(lines)))
    for i in range(start, len(lines)): print("%4d: %s" % (i + 1, lines[i].rstrip()))


def _is_binary(path):
    try:
        with open(path, 'rb') as f:
            return b'\x00' in f.read(1024)
    except Exception:
        return True


def _human_size(n):
    if n >= 1024 * 1024: return '%.1f MB' % (n / (1024 * 1024))
    if n >= 1024: return '%.1f KB' % (n / 1024)
    return '%d B' % n


def _classify_file(rel_path, filename):
    rl, nl = rel_path.replace('\\', '/').lower(), filename.lower()
    ext = Path(filename).suffix.lower()
    if 'libs/' in rl or nl.startswith('lib') or nl.startswith('ace'):
        return 'vendored-lib'
    if 'localization/' in rl or 'locales/' in rl or nl.startswith('modl_'):
        return 'localization'
    if ext in ('.png', '.blp', '.tga', '.ttf', '.mp3', '.ogg'):
        return 'binary-asset'
    if ext in ('.md', '.txt', '.rst', '.html'): return 'documentation'
    if ext in ('.toc', '.pkgmeta', '.luacheckrc', '.gitignore', '.gitattributes'):
        return 'config'
    if '.github/' in rl: return 'config'
    if ext in ('.lua', '.xml', '.py', '.ps1', '.bat', '.sh'): return 'source-code'
    return 'unknown'


def _read_lines_safe(path, max_lines=None):
    try:
        with open(path, encoding='utf-8', errors='replace') as f:
            return [next(f) for _ in range(max_lines)] if max_lines else f.readlines()
    except Exception:
        return []


def _detect_version(path, ext, name_lower):
    """Detect version string from a file based on its type."""
    if ext == '.toc':
        for line in _read_lines_safe(path, 30):
            m = re.match(r'^##\s*Version:\s*(.+)', line.strip())
            if m: return m.group(1).strip()
    elif name_lower in ('changelog.md', 'changelog'):
        for line in _read_lines_safe(path, 50):
            m = re.search(r'(?:^##?\s*\[?)(v?\d+\.\d+[\.\d\w-]*)', line)
            if m: return m.group(1)
    elif ext == '.md':
        for line in _read_lines_safe(path, 20):
            m = re.search(r'(?:^##?\s*[Vv]ersion[:\s]*)([\d]+\.[\d]+[\.\d\w-]*)', line)
            if m: return m.group(1)
            m = re.search(r'\bv?(\d+\.\d+\.\d+(?:-[\w.]+)?)\b', line)
            if m: return m.group(1)
    return None


_SKIP_NAMES = {'PROCESS.md', 'PIPELINE_STATE.md'}
_EXCLUDE_DIRS = {'Process', '.git', 'node_modules', '__pycache__', '.venv'}


def cmd_process_intake(args):
    """Pre-process Pipeline intake directory for structured analysis."""
    process_dir = Path(args.process_dir).resolve()
    hub = Path(args.hub).resolve() if args.hub else REPO_ROOT
    if not process_dir.is_dir():
        print("ERROR: Process directory not found: %s" % process_dir)
        sys.exit(1)

    # 1) INVENTORY
    inventory = []
    for root, dirs, files in os.walk(process_dir):
        dirs[:] = [d for d in dirs if d not in ('.git', '__pycache__')]
        for fname in files:
            if fname in _SKIP_NAMES or fname.startswith('Process_Analysis_Log'):
                continue
            fpath = Path(root) / fname
            rel_str = str(fpath.relative_to(process_dir)).replace('\\', '/')
            lc = -1
            if not _is_binary(fpath):
                try:
                    with open(fpath, encoding='utf-8', errors='replace') as f:
                        lc = sum(1 for _ in f)
                except Exception:
                    pass
            inventory.append({
                'path': fpath, 'rel': rel_str, 'name': fname,
                'size': fpath.stat().st_size, 'ext': fpath.suffix.lower(),
                'lines': lc, 'category': _classify_file(rel_str, fname),
            })

    # 2) CANONICAL MATCHING -- build hub file index
    hub_index = defaultdict(list)
    for root, dirs, files in os.walk(hub):
        dirs[:] = [d for d in dirs if d not in _EXCLUDE_DIRS]
        for fname in files:
            fp = Path(root) / fname
            hub_index[fname].append((fp, str(fp.relative_to(hub)).replace('\\', '/')))

    for item in inventory:
        item.update({'match': 'NO MATCH', 'canonical': None, 'canonical_all': []})
        matches = hub_index.get(item['name'], [])
        for abs_p, rel_h in matches:
            if rel_h == item['rel']:
                item['match'], item['canonical'] = 'EXACT PATH', abs_p
                break
        if item['match'] == 'NO MATCH' and matches:
            item['canonical_all'] = list(matches)
            item['match'] = 'NAME MATCH'
            if len(matches) == 1:
                item['canonical'] = matches[0][0]

    # 3) BATCH DIFF
    for item in inventory:
        if item['canonical'] is None:
            item.update(diff='NEW', added=0, removed=0); continue
        if _is_binary(item['path']) or _is_binary(item['canonical']):
            item.update(diff='BINARY', added=0, removed=0); continue
        d = list(difflib.unified_diff(
            _read_lines_safe(item['canonical']), _read_lines_safe(item['path']),
            lineterm=''))
        a = sum(1 for l in d if l.startswith('+') and not l.startswith('+++'))
        r = sum(1 for l in d if l.startswith('-') and not l.startswith('---'))
        item.update(diff='CHANGED' if a or r else 'IDENTICAL', added=a, removed=r)

    # 4) VERSION DETECTION
    versions = {}
    for item in inventory:
        ver = _detect_version(item['path'], item['ext'], item['name'].lower())
        if ver:
            canon_ver = (_detect_version(item['canonical'], item['ext'],
                         item['name'].lower()) if item['canonical'] else None)
            versions[item['rel']] = {'process': ver, 'canonical': canon_ver}

    # 6) PATTERN DETECTION
    total = len(inventory)
    if total == 0:
        pattern = 'EMPTY'
    elif total == 1:
        pattern = 'SINGLE_FILE'
    else:
        matched = sum(1 for i in inventory if i['match'] != 'NO MATCH')
        has_ver_diff = any(v['canonical'] and v['process'] != v['canonical']
                          for v in versions.values())
        if matched / total > 0.8 and has_ver_diff: pattern = 'VERSION_UPDATE'
        elif (total - matched) / total > 0.8: pattern = 'NEW_CONTENT'
        else: pattern = 'MIXED_INTAKE'

    # BUILD REPORT
    out = ['## Process Intake Report',
           'Generated: %s' % datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
           'Process dir: %s' % process_dir, 'Hub root: %s' % hub, '']
    ver_summary = ''
    for v in versions.values():
        if v['canonical'] and v['process'] != v['canonical']:
            ver_summary = ' | Version: %s -> %s' % (v['canonical'], v['process']); break
        elif v['process'] and not v['canonical']:
            ver_summary = ' | Version: %s (new)' % v['process']; break
    out += ['### Summary', 'Files: %d | Pattern: %s%s' % (total, pattern, ver_summary), '']

    changed = sorted([i for i in inventory if i['diff'] == 'CHANGED'],
                     key=lambda x: x['added'] + x['removed'], reverse=True)
    out.append('### Changed Files (%d)' % len(changed))
    if changed:
        out += ['| File | Category | +Lines | -Lines |', '|------|----------|--------|--------|']
        out += ['| %s | %s | +%d | -%d |' % (i['rel'], i['category'], i['added'], i['removed'])
                for i in changed]
    else: out.append('(none)')
    out.append('')

    new = [i for i in inventory if i['diff'] == 'NEW']
    out.append('### New Files (%d)' % len(new))
    if new:
        out += ['| File | Category | Lines | Size |', '|------|----------|-------|------|']
        out += ['| %s | %s | %s | %s |' % (i['rel'], i['category'],
                '%d' % i['lines'] if i['lines'] >= 0 else 'binary',
                _human_size(i['size'])) for i in new]
    else: out.append('(none)')
    out.append('')

    identical = [i for i in inventory if i['diff'] == 'IDENTICAL']
    out.append('### Identical Files (%d)' % len(identical))
    if identical:
        by_cat = defaultdict(list)
        for i in identical: by_cat[i['category']].append(i['rel'])
        for cat in sorted(by_cat): out.append('**%s**: %s' % (cat, ', '.join(sorted(by_cat[cat]))))
    else: out.append('(none)')
    out.append('')

    if pattern == 'VERSION_UPDATE':
        toc_items = [i for i in inventory if i['ext'] == '.toc' and i['canonical']]
        if toc_items:
            proj_dir = toc_items[0]['canonical'].parent
            proc_names = {i['name'] for i in inventory}
            orphans = []
            for root, dirs, files in os.walk(proj_dir):
                dirs[:] = [d for d in dirs if d not in ('.git', '__pycache__')]
                orphans += [str((Path(root) / f).relative_to(proj_dir)).replace('\\', '/')
                            for f in files if f not in proc_names]
            out.append('### Canonical-Only Files (%d)' % len(orphans))
            out += ['- %s' % o for o in sorted(orphans)] if orphans else ['(none)']
            out.append('')

    if versions:
        out.append('### Version Info')
        for rel, v in sorted(versions.items()):
            if v['canonical']:
                out.append('- %s: %s -> %s' % (rel, v['canonical'], v['process']))
            else:
                out.append('- %s: %s (new)' % (rel, v['process']))
        out.append('')

    _write_result(out)


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
    p = sub.add_parser('search', help='Grep for pattern in files matching glob or file path')
    p.add_argument('pattern', help='Regex pattern (use commas for OR: "pat1,pat2,pat3")')
    p.add_argument('glob', help='File glob (e.g. *.lua) or specific file path (e.g. UI/UI_Home.lua)')
    p.add_argument('--context', '-C', type=int, default=0, help='Context lines')
    p.add_argument('--case-sensitive', '-s', action='store_true', help='Case-sensitive (default: insensitive)')

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

    # process-intake
    p = sub.add_parser('process-intake', help='Pre-process Pipeline intake directory')
    p.add_argument('process_dir', help='Path to Process/ directory')
    p.add_argument('--hub', default=None, help='Hub root (default: 2 levels up from script)')

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
        'process-intake': cmd_process_intake,
    }
    dispatch[args.command](args)


if __name__ == '__main__':
    main()
