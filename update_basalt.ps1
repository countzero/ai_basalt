#Requires -Version 7.0

<#
.SYNOPSIS
Update the Basalt submodule to a commit and build its engine.

.DESCRIPTION
Checks out the requested Basalt commit in vendor/basalt, installs Basalt's
Python packages into vendor/basalt/.venv and builds bin\basalt.exe and its
tools with Visual Studio 2022, CUDA 13 and Ninja.

Basalt publishes no tags, releases or ready-made engines, so a version is a
commit of upstream's main and the engine is built here.

Everything that can fail before the build (the commit, a running server, the
toolchain) is checked before anything is changed. A failed build puts the old
commit and the old bin\ back. Nothing is committed, and the server is neither
started nor stopped.

.PARAMETER commit
A commit of upstream's main, or "main" for its newest commit.
Defaults to the newest commit of main whose "ci" workflow passed.

.PARAMETER jobs
Parallel compile jobs. Defaults to Ninja's choice (all cores). Lower it while
another server on this machine serves clients.

.PARAMETER help
Shows the manual on how to use this script.

.EXAMPLE
.\update_basalt.ps1

.EXAMPLE
.\update_basalt.ps1 -commit 8d73a39

.EXAMPLE
.\update_basalt.ps1 -commit main -jobs 8
#>

Param (
    [String]
    $commit,

    [Int]
    $jobs = 0,

    [switch]
    $help
)

if ($help) {
    Get-Help -Detailed $PSCommandPath
    exit
}

$ErrorActionPreference = "Stop"

$stopwatch = [System.Diagnostics.Stopwatch]::startNew()

$basaltPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "vendor\basalt"))
$binPath = Join-Path $basaltPath "bin"
$buildPath = Join-Path $basaltPath "build"
$previousPath = Join-Path $buildPath "bin.previous"
$buildScript = Join-Path $buildPath "update_basalt.cmd"
$venvPython = Join-Path $basaltPath ".venv\Scripts\python.exe"
$binaries = @("basalt.exe", "basalt-bench.exe", "basalt-probe.exe", "basalt-vision.exe")

function Invoke-BasaltGit {
    $output = git -C $basaltPath @args
    if ($LASTEXITCODE -ne 0) {
        throw "git $($args -join ' ') failed with exit code ${LASTEXITCODE}."
    }
    $output
}

function Invoke-Checked {
    Param ([String] $what, [ScriptBlock] $block)
    & $block
    if ($LASTEXITCODE -ne 0) {
        throw "${what} failed with exit code ${LASTEXITCODE}."
    }
}

if (-not (Test-Path -Path (Join-Path $basaltPath ".git"))) {
    throw "vendor/basalt is not checked out. Run 'git submodule update --init' first."
}

# The server is a python.exe from vendor\basalt\.venv, started by
# bin\basalt.exe with that binary's absolute path on its command line, so the
# folder finds every part of it and never a Strata server. Shells whose
# command line names the folder hold no files open.
$shells = @("pwsh.exe", "powershell.exe", "cmd.exe", "conhost.exe", "OpenConsole.exe", "WindowsTerminal.exe")

$blockers = Get-CimInstance -ClassName Win32_Process | Where-Object {
    $_.ProcessId -ne $PID -and (
        ($_.ExecutablePath -and $_.ExecutablePath.StartsWith($basaltPath, [StringComparison]::OrdinalIgnoreCase)) -or
        ($_.Name -notin $shells -and $_.CommandLine -and
            $_.CommandLine.IndexOf($basaltPath, [StringComparison]::OrdinalIgnoreCase) -ge 0)
    )
}

if ($blockers) {
    $list = ($blockers | ForEach-Object { "  PID $($_.ProcessId)  $($_.Name)  $($_.CommandLine)" }) -join "`n"
    throw "Basalt is running:`n${list}`nStop the server and re-run. Other clients depend on it, so this script does not stop it."
}

if (Invoke-BasaltGit status --porcelain --untracked-files=no) {
    throw "vendor/basalt has local changes. Upstream's code is never edited here: check them with 'git -C vendor\basalt status'."
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"

if (-not (Test-Path -Path $vswhere)) {
    throw "Visual Studio 2022 is not installed (no vswhere.exe)."
}

$vsPath = & $vswhere -latest -version "[17.0,18.0)" -property installationPath

# Visual Studio's own CMake and Ninja, so a CMake release candidate or another
# Ninja on the PATH never builds the engine.
$vcvars = Join-Path "$vsPath" "VC\Auxiliary\Build\vcvars64.bat"
$cmake = Join-Path "$vsPath" "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
$ninja = Join-Path "$vsPath" "Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"

foreach ($tool in @($vcvars, $cmake, $ninja)) {
    if (-not $vsPath -or -not (Test-Path -Path $tool)) {
        throw "Visual Studio 2022 lacks '${tool}'. Install the workload 'Desktop development with C++' with its CMake tools."
    }
}

if (-not $env:CUDA_PATH -or -not (Test-Path -Path (Join-Path $env:CUDA_PATH "bin\nvcc.exe"))) {
    throw "No CUDA Toolkit found (CUDA_PATH). Basalt needs CUDA 13 or newer."
}

$nvccVersion = [regex]::Match((& (Join-Path $env:CUDA_PATH "bin\nvcc.exe") --version) -join "`n", 'release (\d+)\.(\d+)')

if (-not $nvccVersion.Success -or [int]$nvccVersion.Groups[1].Value -lt 13) {
    throw "CUDA_PATH points to CUDA $($nvccVersion.Groups[1].Value).$($nvccVersion.Groups[2].Value). Basalt needs CUDA 13 or newer."
}

# The engine links the CUDA runtime and cuBLAS as DLLs and its build copies
# neither, so Windows has to find them on the PATH.
if (-not (Get-Command -Name "cudart64_13.dll" -CommandType "Application" -ErrorAction "SilentlyContinue")) {
    throw "cudart64_13.dll is not on the PATH. Add '$(Join-Path $env:CUDA_PATH 'bin\x64')' to the PATH."
}

$systemPython = Get-Command -Name "python" -CommandType "Application" -ErrorAction "SilentlyContinue" | Select-Object -First 1

if (-not (Test-Path -Path $venvPython) -and -not $systemPython) {
    throw "No python on the PATH to create vendor/basalt/.venv with. Basalt needs Python 3.10 or newer."
}

Write-Host "[Git] Fetching Basalt's main..." -ForegroundColor "Yellow"

Invoke-BasaltGit fetch --quiet origin main

$repository = [regex]::Match(
    (Invoke-BasaltGit remote get-url origin),
    'github\.com[:/](.+?)(\.git)?$'
).Groups[1].Value

function Test-CiPassed {
    Param ([String] $sha)
    $runs = Invoke-RestMethod -Uri "https://api.github.com/repos/${repository}/actions/runs?head_sha=${sha}&status=success&per_page=20"
    [bool]($runs.workflow_runs | Where-Object { $_.name -eq "ci" })
}

if (!$commit) {
    $runs = Invoke-RestMethod -Uri "https://api.github.com/repos/${repository}/actions/runs?branch=main&status=success&per_page=50"
    $commit = $runs.workflow_runs | Where-Object { $_.name -eq "ci" } | Select-Object -First 1 -ExpandProperty "head_sha"

    if (!$commit) {
        throw "None of the newest runs on main passed the ci workflow. Name a commit with -commit."
    }
}

# The submodule's local main is never pulled, so the name means upstream's.
$ref = if ($commit -eq "main") { "origin/main" } else { $commit }
$newCommit = git -C $basaltPath rev-parse --verify --quiet "${ref}^{commit}"

if ($LASTEXITCODE -ne 0 -or !$newCommit) {
    throw "Basalt has no commit '${commit}'."
}

if (-not (Invoke-BasaltGit branch --remotes --contains $newCommit | Where-Object { $_.Trim() -eq "origin/main" })) {
    throw "Basalt's commit ${newCommit} is not on upstream's main."
}

$oldCommit = Invoke-BasaltGit rev-parse HEAD
$oldShort = Invoke-BasaltGit rev-parse --short=12 $oldCommit
$newShort = Invoke-BasaltGit rev-parse --short=12 $newCommit
$subject = Invoke-BasaltGit log -1 --format=%s $newCommit

Write-Host "Updating Basalt..." -ForegroundColor "Yellow"
Write-Host "Commit: ${oldShort} -> ${newShort} (${subject})" -ForegroundColor "DarkYellow"

if ($oldCommit -ne $newCommit) {
    Write-Host "Changes: https://github.com/${repository}/compare/${oldShort}...${newShort}" -ForegroundColor "DarkYellow"
}

if (-not (Test-CiPassed -sha $newCommit)) {
    Write-Host "No passed ci run exists for ${newShort}: the build is untested upstream." -ForegroundColor "DarkYellow"
}

$hadBinaries = Test-Path -Path (Join-Path $binPath "basalt.exe")

try {
    Write-Host "[Git] Checking out ${newShort}..." -ForegroundColor "Yellow"

    Invoke-BasaltGit checkout --quiet --detach $newCommit

    if (-not (Test-Path -Path $venvPython)) {
        Write-Host "[Python] Creating vendor\basalt\.venv..." -ForegroundColor "Yellow"
        Invoke-Checked "python -m venv" { & $systemPython.Source -m venv (Join-Path $basaltPath ".venv") }
    }

    Write-Host "[Python] Installing requirements.txt..." -ForegroundColor "Yellow"

    Invoke-Checked "pip install" {
        & $venvPython -m pip install --disable-pip-version-check --quiet --requirement (Join-Path $basaltPath "requirements.txt")
    }

    New-Item -Path $buildPath -ItemType "directory" -Force | Out-Null

    if ($hadBinaries) {
        Remove-Item -Path $previousPath -Recurse -Force -ErrorAction "SilentlyContinue"
        Copy-Item -Path $binPath -Destination $previousPath -Recurse
    }

    # vcvars64.bat and the build share one cmd.exe, so the Visual Studio
    # environment never leaks into the calling shell.
    $parallel = if ($jobs -gt 0) { "--parallel ${jobs}" } else { "" }

    Set-Content -Path $buildScript -Encoding "ascii" -Value @"
@echo off
call "${vcvars}" >nul || exit /b 1
"${cmake}" -S "${basaltPath}" -B "${buildPath}" -G Ninja -DCMAKE_BUILD_TYPE=Release "-DCMAKE_MAKE_PROGRAM=${ninja}" || exit /b 1
"${cmake}" --build "${buildPath}" ${parallel} || exit /b 1
"@

    Write-Host "[Build] Configuring and building (the first build takes a long time)..." -ForegroundColor "Yellow"

    Invoke-Checked "The build" { & cmd.exe /d /c $buildScript }

    foreach ($binary in $binaries) {
        if (-not (Test-Path -Path (Join-Path $binPath $binary))) {
            throw "The build made no bin\${binary}."
        }
    }

    & (Join-Path $binPath "basalt.exe") --help *> $null

    if ($LASTEXITCODE -ne 0) {
        throw "bin\basalt.exe --help failed with exit code ${LASTEXITCODE}: a DLL it needs is probably missing."
    }

} catch {
    Write-Host "Putting back ${oldShort} and its bin\..." -ForegroundColor "Red"

    git -C $basaltPath checkout --quiet --detach $oldCommit

    if ($hadBinaries -and (Test-Path -Path $previousPath)) {
        Remove-Item -Path $binPath -Recurse -Force -ErrorAction "SilentlyContinue"
        Copy-Item -Path $previousPath -Destination $binPath -Recurse
    }

    throw
}

git -C $PSScriptRoot status --short

$stopwatch.Stop()
$durationInSeconds = [Math]::Floor([Decimal]($stopwatch.Elapsed.TotalSeconds))

Write-Host "Updated Basalt ${oldShort} -> ${newShort} in ${durationInSeconds} seconds." -ForegroundColor "Yellow"
Write-Host "Next: README.md -> Update Basalt, from step 3 (start, benchmark, commit)." -ForegroundColor "Yellow"
