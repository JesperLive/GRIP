# GRIP: Long-Running Process Helper for Desktop Commander
#
# DC MCP transport has a 60-second timeout ceiling that cannot be configured.
# This helper wraps long-running Python commands so they work reliably via DC.
#
# Usage (from DC start_process):
#   cd C:\Users\dries\Documents\GRIP\Tools
#   python dc_long_run.py "python some_script.py --args"
#   python dc_long_run.py --inline "import something; something.run()"
#
# How it works:
#   1. Launches the command as a subprocess with stdout/stderr piped
#   2. Streams output to both console AND a timestamped log file
#   3. Returns immediately-useful info (PID, log path) within seconds
#   4. Full output is always available in the log file
#
# Log files: %TEMP%/dc_long_run_<timestamp>.log
# Author: MrSataana (GRIP project)
import sys
import os
import subprocess
import time
import argparse
import tempfile

sys.stdout.reconfigure(encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description="DC long-run process wrapper")
    parser.add_argument('command', nargs='?', help="Shell command to run")
    parser.add_argument('--inline', type=str, default=None,
                        help="Python code to execute inline (runs via python -c)")
    parser.add_argument('--timeout', type=int, default=600,
                        help="Max seconds before killing subprocess (default: 600)")
    parser.add_argument('--cwd', type=str, default=None,
                        help="Working directory (default: script's directory)")
    args = parser.parse_args()

    if not args.command and not args.inline:
        parser.print_help()
        sys.exit(1)

    if args.inline:
        cmd = ['python', '-c',
               'import sys; sys.stdout.reconfigure(encoding="utf-8"); ' + args.inline]
    else:
        cmd = args.command

    timestamp = time.strftime('%Y%m%d_%H%M%S')
    log_path = os.path.join(tempfile.gettempdir(), 'dc_long_run_%s.log' % timestamp)
    cwd = args.cwd or os.path.dirname(os.path.abspath(__file__))

    print("=== DC Long-Run Wrapper ===")
    print("Log: %s" % log_path)
    print("CWD: %s" % cwd)
    print("Cmd: %s" % (cmd if isinstance(cmd, str) else ' '.join(cmd)))
    print("Timeout: %ds" % args.timeout)
    print("===")
    print()
    sys.stdout.flush()

    t0 = time.time()
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            cwd=cwd,
            shell=isinstance(cmd, str),
            text=True,
            encoding='utf-8',
            errors='replace',
        )

        lines = []
        with open(log_path, 'w', encoding='utf-8') as log_f:
            log_f.write("# dc_long_run.py log -- %s\n" % time.strftime('%Y-%m-%d %H:%M:%S'))
            log_f.write("# cmd: %s\n" % (cmd if isinstance(cmd, str) else ' '.join(cmd)))
            log_f.write("# cwd: %s\n\n" % cwd)
            log_f.flush()

            for line in proc.stdout:
                print(line, end='')
                sys.stdout.flush()
                log_f.write(line)
                log_f.flush()
                lines.append(line)

                if time.time() - t0 > args.timeout:
                    proc.kill()
                    msg = "\n!!! TIMEOUT after %ds -- process killed !!!\n" % args.timeout
                    print(msg)
                    log_f.write(msg)
                    break

        proc.wait(timeout=5)
        elapsed = time.time() - t0

        footer = "\n=== Done in %.1fs (exit code %d) ===" % (elapsed, proc.returncode)
        print(footer)
        with open(log_path, 'a', encoding='utf-8') as log_f:
            log_f.write(footer + "\n")

    except Exception as e:
        elapsed = time.time() - t0
        err_msg = "\n!!! ERROR after %.1fs: %s !!!" % (elapsed, str(e))
        print(err_msg)
        with open(log_path, 'a', encoding='utf-8') as log_f:
            log_f.write(err_msg + "\n")
        sys.exit(1)

    print("Full log: %s" % log_path)
    sys.exit(proc.returncode)


if __name__ == '__main__':
    main()
