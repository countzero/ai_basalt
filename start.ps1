#Requires -Version 7.0

<#
.SYNOPSIS
Start the Basalt server with a tier file.

.DESCRIPTION
Runs vendor\basalt\bin\basalt.exe serve with a tier file from presets\ on the
given port, in this window, until it is stopped with Ctrl+C.

Checks first that the engine is built, that the tier file's model exists and
that no other server (such as Strata) listens on the port. It never stops
another server: stop it yourself, it may have clients.

.PARAMETER tier
The tier file: its name in presets\ (with or without .json) or a path.
Defaults to the only tier file in presets\.

.PARAMETER port
The port to listen on.

.PARAMETER help
Shows the manual on how to use this script.

.EXAMPLE
.\start.ps1

.EXAMPLE
.\start.ps1 -tier qwen3.8-flash-next.unsloth-ud-iq4_xs.24GB_VRAM_192GB_RAM
#>

Param (
    [String]
    $tier,

    [Int]
    $port = 8083,

    [switch]
    $help
)

if ($help) {
    Get-Help -Detailed $PSCommandPath
    exit
}

$ErrorActionPreference = "Stop"

$presetsPath = Join-Path $PSScriptRoot "presets"
$basalt = Join-Path $PSScriptRoot "vendor\basalt\bin\basalt.exe"

if (-not (Test-Path -Path $basalt)) {
    throw "vendor\basalt\bin\basalt.exe is missing. Run .\update_basalt.ps1 first."
}

if (!$tier) {
    $tiers = @(Get-ChildItem -Path $presetsPath -Filter "*.json" -File)

    if ($tiers.Count -ne 1) {
        $list = ($tiers | ForEach-Object { "  $($_.BaseName)" }) -join "`n"
        throw "Name the tier file with -tier:`n${list}"
    }

    $configPath = $tiers[0].FullName
} elseif (Test-Path -Path $tier -PathType "Leaf") {
    $configPath = (Resolve-Path -Path $tier).Path
} else {
    $configPath = Join-Path $presetsPath ($tier -replace '\.json$', '') | ForEach-Object { "$_.json" }

    if (-not (Test-Path -Path $configPath)) {
        throw "No tier file '${tier}' in presets\."
    }
}

$model = (Get-Content -Raw -Path $configPath | ConvertFrom-Json).server.model

if (-not $model -or -not (Test-Path -Path $model)) {
    throw "The tier file's model '${model}' does not exist. Build it as README.md -> Model pack says."
}

$listener = Get-NetTCPConnection -LocalPort $port -State "Listen" -ErrorAction "SilentlyContinue" | Select-Object -First 1

if ($listener) {
    $owner = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $($listener.OwningProcess)"
    throw "Port ${port} is taken by PID $($owner.ProcessId) ($($owner.Name)): $($owner.CommandLine)`nStop that server and re-run. It may have clients, so this script does not stop it."
}

Write-Host "Starting Basalt..." -ForegroundColor "Yellow"
Write-Host "Version: $(git -C (Join-Path $PSScriptRoot 'vendor\basalt') rev-parse --short=12 HEAD)" -ForegroundColor "DarkYellow"
Write-Host "Tier: $(Split-Path -Path $configPath -LeafBase)" -ForegroundColor "DarkYellow"
Write-Host "Port: ${port}" -ForegroundColor "DarkYellow"

& $basalt serve --config $configPath --port $port

exit $LASTEXITCODE
