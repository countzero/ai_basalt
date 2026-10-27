#Requires -Version 7.0

<#
.SYNOPSIS
Benchmark the running Basalt server with Strata's tools/strata_bench.py.

.DESCRIPTION
Runs the default suite of Strata's tools/strata_bench.py (copied into
tools/strata, see AGENTS.md) against the server that is already running,
writes the results to .tmp/bench/basalt-<commit>/ and prints the four numbers
of README.md -> Tiers.

It is the suite ai_strata's benchmark.ps1 runs against Strata, so the numbers
of both servers compare directly.

The server is neither started nor stopped: start it as README.md -> Usage says.

.PARAMETER url
The address of the running server.

.PARAMETER compare
An earlier results folder to print beside this run, for example
.tmp\bench\basalt-8d73a39477690. A folder that holds several runs uses the
newest. A results folder of ai_strata's benchmark.ps1 works as well.

.PARAMETER arguments
Passed on to tools/strata/strata_bench.py unchanged, for example --long or
--clients 2. See its --help.

.PARAMETER help
Shows the manual on how to use this script.

.EXAMPLE
.\benchmark.ps1

.EXAMPLE
.\benchmark.ps1 -compare ..\ai_strata\.tmp\bench\v0.2.4.2_engine-0.1.48

.EXAMPLE
.\benchmark.ps1 --runs 5 --long
#>

# Without this, "--runs 5" binds "--runs" to -url by position.
[CmdletBinding(PositionalBinding = $false)]
Param (
    [String]
    $url = "http://127.0.0.1:8084",

    [String]
    $compare,

    [Parameter(ValueFromRemainingArguments)]
    [String[]]
    $arguments,

    [switch]
    $help
)

if ($help) {
    Get-Help -Detailed $PSCommandPath
    exit
}

$ErrorActionPreference = "Stop"

$stopwatch = [System.Diagnostics.Stopwatch]::startNew()

$basaltPath = Join-Path $PSScriptRoot "vendor\basalt"
$python = Join-Path $basaltPath ".venv\Scripts\python.exe"
$bench = Join-Path $PSScriptRoot "tools\strata\strata_bench.py"
$invariant = [System.Globalization.CultureInfo]::InvariantCulture

function Find-Results {
    Param ([String] $path)

    if ((Test-Path -Path $path -PathType "Leaf") -and (Split-Path -Path $path -Leaf) -eq "results.json") {
        return (Resolve-Path -Path $path).Path
    }

    Get-ChildItem -Path $path -Filter "results.json" -Recurse -File -ErrorAction "SilentlyContinue" |
        Sort-Object -Property "LastWriteTime" -Descending |
        Select-Object -First 1 -ExpandProperty "FullName"
}

function Format-Number {
    Param ($value, [String] $format, [String] $unit)

    if ($null -eq $value) {
        return "skipped"
    }

    "$(([double]$value).ToString($format, $invariant)) ${unit}"
}

if (-not (Test-Path -Path $python)) {
    throw "vendor/basalt/.venv is missing. Run .\update_basalt.ps1 first."
}

$compareResults = $null

if ($compare) {
    $compareResults = Find-Results -path $compare

    if (!$compareResults) {
        throw "No results.json found in '${compare}'."
    }
}

try {
    $health = Invoke-RestMethod -Uri "${url}/health" -TimeoutSec 10
    $models = Invoke-RestMethod -Uri "${url}/v1/models" -TimeoutSec 10
} catch {
    throw "No Basalt server answers at ${url}. Start it as README.md -> Usage says, wait for 'ready', and re-run."
}

if ($health.service -ne "basalt") {
    throw "The server at ${url} is '$($health.service)', not Basalt. Benchmark Strata with ai_strata's benchmark.ps1."
}

$model = @($models.data.id)[0]
$commit = git -C $basaltPath rev-parse --short=12 HEAD
$outPath = Join-Path $PSScriptRoot ".tmp\bench\basalt-${commit}"

New-Item -Path $outPath -ItemType "directory" -Force | Out-Null

Write-Host "Benchmarking Basalt..." -ForegroundColor "Yellow"
Write-Host "Server: ${url} (${model})" -ForegroundColor "DarkYellow"
Write-Host "Version: ${commit}" -ForegroundColor "DarkYellow"
Write-Host "Results: ${outPath}" -ForegroundColor "DarkYellow"

if ($compareResults) {
    Write-Host "Compare: ${compareResults}" -ForegroundColor "DarkYellow"
}

$startedAt = Get-Date
$benchEnvironment = @{ STRATA_BENCH_MODEL = $model; STRATA_BENCH_SERVER = "Basalt"; STRATA_BENCH_COMMIT = $commit }
$previousEnvironment = @{}

foreach ($name in $benchEnvironment.Keys) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
    [Environment]::SetEnvironmentVariable($name, $benchEnvironment[$name])
}

try {

    $benchArguments = @("-u", $bench, "--url", $url, "--out", $outPath)

    if ($compareResults) {
        $benchArguments += @("--compare", $compareResults)
    }

    & $python @benchArguments @arguments

    if ($LASTEXITCODE -ne 0) {
        throw "tools/strata/strata_bench.py failed with exit code ${LASTEXITCODE}."
    }

} finally {
    foreach ($name in $previousEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name])
    }
}

$resultsPath = Get-ChildItem -Path $outPath -Filter "results.json" -Recurse -File |
    Where-Object { $_.LastWriteTime -ge $startedAt } |
    Sort-Object -Property "LastWriteTime" -Descending |
    Select-Object -First 1 -ExpandProperty "FullName"

if (!$resultsPath) {
    throw "tools/strata/strata_bench.py wrote no results.json under ${outPath}."
}

$results = (Get-Content -Raw -Path $resultsPath | ConvertFrom-Json).results

$row = [ordered]@{
    "Basalt"          = $commit
    "Chat decode"     = Format-Number -value $results.chat.decode_tps.median -format "0.0" -unit "tok/s"
    "16K prompt"      = Format-Number -value $results.prompts."16K".prompt_tps.median -format "0" -unit "tok/s"
    "Agent decode"    = Format-Number -value $results.agent.turn_decode_tps.median -format "0.0" -unit "tok/s"
    "Agent cache hit" = Format-Number -value $results.agent.hit_pct.median -format "0.0" -unit "%"
}

$stopwatch.Stop()
$durationInSeconds = [Math]::Floor([Decimal]($stopwatch.Elapsed.TotalSeconds))

Write-Host "README.md -> Tiers (medians):" -ForegroundColor "Yellow"
[pscustomobject]$row | Format-Table -AutoSize | Out-Host
Write-Host "Finished the benchmark in ${durationInSeconds} seconds: ${resultsPath}" -ForegroundColor "Yellow"
