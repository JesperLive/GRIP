# dc-helpers.ps1 -- Desktop Commander workarounds for GRIP Cowork sessions
# Dot-source this at the start of any start_process call that needs exe output.
#
# CANONICAL LOCATION: C:\Users\dries\Hub\GRIP\Tools\dc-helpers.ps1
# Hard-linked into each repo's Tools/ folder via setup-addon-junctions.ps1.
#
# WHY: DC's start_process can't capture stdout from external .exe processes.
#      This wrapper uses Start-Process with file-based redirection to bypass the bug.
#
# USAGE (pass arguments as space-separated, quote values with spaces):
#   . "C:\Users\dries\Hub\GRIP\Tools\dc-helpers.ps1"
#   Run-Git status --short
#   Run-Git log --oneline -5
#   Run-Git tag v1.0.0
#   Run-Git push origin v1.0.0
#   Run-Exe "node" "--version"
#
# GIT CREDENTIAL SETUP (2026-03-18):
#   gh auth setup-git has been run -- git uses gh as the credential helper
#   for github.com (per-host override in ~/.gitconfig). Run-Git push/tag
#   operations use the gh CLI token (keyring), not Git Credential Manager.
#   If auth breaks: re-run gh auth setup-git
#   Jesper commits/pushes code via GitHub Desktop. Cowork handles tag+push for releases.

# Auto-detect repo root from script location (works via hard links)
$script:GRIP_DIR = (Get-Item $PSScriptRoot).Parent.FullName

function Run-Exe {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(ValueFromRemainingArguments)][string[]]$Arguments
    )

    # Resolve command to full path if not already absolute
    $exePath = $Command
    if (-not [System.IO.Path]::IsPathRooted($Command)) {
        $searchPaths = @(
            "C:\Program Files\Git\cmd",
            "C:\Program Files\Git\bin",
            "C:\Program Files\nodejs",
            "C:\Program Files\GitHub CLI",
            "C:\Python314",
            "C:\Python314\Scripts"
        )
        foreach ($dir in $searchPaths) {
            $candidate = Join-Path $dir "$Command.exe"
            if (Test-Path $candidate) {
                $exePath = $candidate
                break
            }
        }
    }

    $outFile = Join-Path $env:TEMP "dc_exe_out.txt"
    $errFile = Join-Path $env:TEMP "dc_exe_err.txt"
    if (Test-Path $outFile) { Remove-Item $outFile -Force }
    if (Test-Path $errFile) { Remove-Item $errFile -Force }

    # Re-quote any argument that contains spaces so Start-Process preserves it
    # as a single token on the command line. PowerShell correctly parses quoted
    # args from DC's command string (e.g., -m "Message with spaces" arrives as
    # one element), but joining with -join ' ' would lose that grouping.
    $parts = foreach ($arg in $Arguments) {
        if ($arg -match '\s' -and $arg -notmatch '^".*"$') {
            '"{0}"' -f ($arg -replace '"', '\"')
        } else {
            $arg
        }
    }
    $argLine = ($parts -join ' ').Trim()

    $spArgs = @{
        FilePath               = $exePath
        NoNewWindow            = $true
        Wait                   = $true
        RedirectStandardOutput = $outFile
        RedirectStandardError  = $errFile
    }
    if ($argLine) { $spArgs.ArgumentList = $argLine }

    $proc = Start-Process @spArgs -PassThru

    if (Test-Path $outFile) {
        $stdout = Get-Content $outFile -Raw
        if ($stdout) { Write-Host $stdout.TrimEnd() }
    }
    if (Test-Path $errFile) {
        $stderr = Get-Content $errFile -Raw
        if ($stderr) { Write-Host "STDERR: $($stderr.TrimEnd())" }
    }

    $global:DC_EXIT = $proc.ExitCode
}

# Convenience wrapper: git with -C pointing at the GRIP repo.
# Passes args individually via splatting so Run-Exe can re-quote as needed.
#   Run-Git log --oneline -5
#   Run-Git commit -m "My commit message"
#   Run-Git push origin v1.5.5
function Run-Git {
    param([Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    $gitArgs = @("-C", $script:GRIP_DIR) + $Arguments
    Run-Exe "git" @gitArgs
}
