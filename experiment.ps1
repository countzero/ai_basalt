#Requires -Version 7.0

<#
.SYNOPSIS
Measure a tier with changed engine settings, one throwaway server per arm.

.DESCRIPTION
For each arm, writes the tier file with the arm's engine settings to a config,
starts Basalt with it in a hidden window, measures it with benchmark.ps1 and
stops it again. The baseline (the tier as it is) runs first and again last, so
the gap between the two shows the noise.

The configs, the server output, each arm's part of the engine log, the results
and summary.md go to .tmp/bench/experiment-<date>/. The tier file is not
changed. The arms bind 127.0.0.1, so other devices do not reach them.

The script never stops another server: it refuses to start while something
listens on the port or uses the GPU, and stops only the servers it started.

Arms:
  baseline    the tier as it is, first and last
  pleram      "ple-io": "ram"
  pcores      "pool-affinity": "p-cores"
  reserve700  "vram-reserve-mib": 700
  kvres       "kv-resident": 32768
  custom      the engine settings given with -custom

.PARAMETER tier
The tier file in presets/ without .json. Defaults to the only one.

.PARAMETER arms
The arms to run, in the order above.

.PARAMETER custom
The engine settings of the arm custom, for example basalt-probe's suggestions
or the winners of a round.

.PARAMETER runs
Passed on to benchmark.ps1 as --runs.

.PARAMETER port
The server port.

.PARAMETER check
Writes and checks the configs, then stops. No server is started.

.PARAMETER help
Shows the manual on how to use this script.

.EXAMPLE
.\experiment.ps1 -check

.EXAMPLE
.\experiment.ps1 -arms baseline,pleram,pcores

.EXAMPLE
.\experiment.ps1 -arms baseline,custom -custom @{ "ple-io" = "ram"; "pool-workers" = 9 }
#>

[CmdletBinding(PositionalBinding = $false)]
Param (
    [String]
    $tier,

    [ValidateSet("baseline", "pleram", "pcores", "reserve700", "kvres", "custom")]
    [String[]]
    $arms = @("baseline", "pleram", "pcores", "reserve700", "kvres"),

    [Hashtable]
    $custom = @{},

    [Int]
    $runs = 5,

    [Int]
    $port = 8084,

    [switch]
    $check,

    [switch]
    $help
)

if ($help) {
    Get-Help -Detailed $PSCommandPath
    exit
}

$ErrorActionPreference = "Stop"

$stopwatch = [System.Diagnostics.Stopwatch]::startNew()

$presetsPath = Join-Path $PSScriptRoot "presets"
$basaltPath = Join-Path $PSScriptRoot "vendor\basalt"
$basalt = Join-Path $basaltPath "bin\basalt.exe"
$benchmarkScript = Join-Path $PSScriptRoot "benchmark.ps1"
$engineLogRoot = Join-Path $HOME ".cache\basalt"
$url = "http://127.0.0.1:${port}"
$invariant = [System.Globalization.CultureInfo]::InvariantCulture

# VRAM in use with no server up; above it, another program would lower the numbers.
$idleVramMiB = 1024

$armOrder = @("baseline", "pleram", "pcores", "reserve700", "kvres", "custom")

$armSettings = @{
    "baseline"   = @{}
    "pleram"     = @{ "ple-io" = "ram" }
    "pcores"     = @{ "pool-affinity" = "p-cores" }
    "reserve700" = @{ "vram-reserve-mib" = 700 }
    "kvres"      = @{ "kv-resident" = 32768 }
    "custom"     = $custom
}

function Format-Settings {
    Param ([Hashtable] $settings)

    if (!$settings.Count) {
        return "-"
    }

    ($settings.Keys | Sort-Object | ForEach-Object { "${_}=$($settings[$_])" }) -join " "
}

function New-ArmConfig {
    Param ([String] $arm, [String] $armPath)

    $config = Get-Content -Raw -Path $tierPath | ConvertFrom-Json
    $settings = $armSettings[$arm]

    foreach ($name in $settings.Keys) {
        $config.engine | Add-Member -NotePropertyName $name -NotePropertyValue $settings[$name] -Force
    }

    $config.server | Add-Member -NotePropertyName "host" -NotePropertyValue "127.0.0.1" -Force

    $configPath = Join-Path $armPath "config.json"
    $config | ConvertTo-Json -Depth 100 | Set-Content -Path $configPath -Encoding "utf8"
    $configPath
}

function Test-ArmConfig {
    Param ([String] $configPath)

    $config = Get-Content -Raw -Path $configPath | ConvertFrom-Json

    if (-not (Test-Path -Path $config.server.model)) {
        throw "${configPath} names a model that does not exist: $($config.server.model)"
    }

    # Basalt would stop at startup on an engine flag its binary does not know.
    $unknown = $config.engine.PSObject.Properties.Name | Where-Object { $engineFlags -notcontains "--$_" }

    if ($unknown) {
        throw "${configPath} names engine flags that basalt.exe does not know: $($unknown -join ', ')"
    }
}

function Get-PortOwner {
    Get-NetTCPConnection -LocalPort $port -State "Listen" -ErrorAction "SilentlyContinue" |
        Select-Object -First 1 -ExpandProperty "OwningProcess"
}

function Get-VramUsed {
    [Int](nvidia-smi --id=0 --query-gpu=memory.used --format=csv,noheader,nounits)
}

function Assert-GpuFree {
    $deadline = (Get-Date).AddSeconds(60)

    while ((Get-VramUsed) -gt $idleVramMiB -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
    }

    $used = Get-VramUsed

    if ($used -gt $idleVramMiB) {
        $apps = (nvidia-smi --query-compute-apps=pid,process_name --format=csv,noheader) -join "; "
        throw "${used} MiB VRAM in use (more than ${idleVramMiB}): another program uses the GPU. ${apps}"
    }
}

function Get-EngineLogLengths {
    $lengths = @{}

    Get-ChildItem -Path $engineLogRoot -Filter "engine.log" -Recurse -File -ErrorAction "SilentlyContinue" |
        ForEach-Object { $lengths[$_.FullName] = $_.Length }

    $lengths
}

# The engine appends to one log per model; this copies what the arm added.
function Copy-EngineLog {
    Param ([Hashtable] $before, [String] $armPath)

    $target = Join-Path $armPath "engine.log"

    Get-ChildItem -Path $engineLogRoot -Filter "engine.log" -Recurse -File -ErrorAction "SilentlyContinue" |
        ForEach-Object {
            $start = if ($before.ContainsKey($_.FullName)) { $before[$_.FullName] } else { 0 }

            if ($_.Length -le $start) {
                return
            }

            $stream = [System.IO.File]::Open($_.FullName, "Open", "Read", "ReadWrite")

            try {
                $stream.Seek($start, "Begin") | Out-Null
                $output = [System.IO.File]::Open($target, "Append", "Write")

                try {
                    $stream.CopyTo($output)
                } finally {
                    $output.Dispose()
                }
            } finally {
                $stream.Dispose()
            }
        }
}

function Start-ArmServer {
    Param ([String] $configPath, [String] $armPath)

    # Hidden window: Windows moves a background console's CPU pool onto the E-cores (upstream issue #93).
    Start-Process -FilePath $basalt -ArgumentList @("serve", "--config", "`"${configPath}`"", "--port", "${port}") `
        -WorkingDirectory $basaltPath -WindowStyle "Hidden" -PassThru `
        -RedirectStandardOutput (Join-Path $armPath "server.log") -RedirectStandardError (Join-Path $armPath "server.err.log")
}

function Wait-Server {
    Param ($process, [Int] $timeoutInSeconds = 600)

    $deadline = (Get-Date).AddSeconds($timeoutInSeconds)

    while ((Get-Date) -lt $deadline) {
        if ($process.HasExited) {
            return $null
        }

        try {
            $health = Invoke-RestMethod -Uri "${url}/health" -TimeoutSec 5

            if ($health.loaded -and $health.service -eq "basalt") {
                return $health
            }
        } catch {
        }

        Start-Sleep -Seconds 5
    }

    $null
}

function Invoke-Smoke {
    $body = @{
        model                = $alias
        max_tokens           = 8
        temperature          = 0
        chat_template_kwargs = @{ enable_thinking = $false }
        messages             = @(@{ role = "user"; content = "Reply with OK." })
    } | ConvertTo-Json -Depth 5

    Invoke-RestMethod -Method "Post" -Uri "${url}/v1/chat/completions" -ContentType "application/json" -Body $body -TimeoutSec 600 |
        Out-Null
}

function Stop-ArmServer {
    Param ($process)

    if (!$process -or $process.HasExited) {
        return
    }

    # /unload answers 409 while a request runs and has no option to wait for it.
    $deadline = (Get-Date).AddSeconds(330)

    while ((Get-Date) -lt $deadline) {
        try {
            Invoke-RestMethod -Method "Post" -Uri "${url}/unload" -ContentType "application/json" -Body "{}" -TimeoutSec 60 |
                Out-Null
            break
        } catch {
            if ($_.Exception.Response.StatusCode.value__ -ne 409) {
                Write-Host "Unload failed ($($_.Exception.Message)), stopping it anyway." -ForegroundColor "DarkYellow"
                break
            }

            Start-Sleep -Seconds 5
        }
    }

    # /T: the server's Python and engine processes hold the VRAM.
    taskkill /PID $process.Id /T /F 2>&1 | Out-Null

    $deadline = (Get-Date).AddSeconds(30)

    while ((Get-PortOwner) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 1
    }

    if (Get-PortOwner) {
        throw "Port ${port} is still taken after stopping process $($process.Id)."
    }
}

function Format-Value {
    Param ($value, [String] $format)

    if ($null -eq $value) {
        return "-"
    }

    ([double]$value).ToString($format, $invariant)
}

function Format-MarkdownTable {
    Param ($rows)

    $names = @($rows[0].Keys)
    $widths = @{}

    foreach ($name in $names) {
        $widths[$name] = (@($name) + @($rows | ForEach-Object { "$($_[$name])" }) | Measure-Object -Property "Length" -Maximum).Maximum
    }

    $lines = @("| " + (($names | ForEach-Object { $_.PadRight($widths[$_]) }) -join " | ") + " |")
    $lines += "| " + (($names | ForEach-Object { "-" * $widths[$_] }) -join " | ") + " |"

    foreach ($row in $rows) {
        $lines += "| " + (($names | ForEach-Object { "$($row[$_])".PadRight($widths[$_]) }) -join " | ") + " |"
    }

    $lines -join "`n"
}

function Invoke-Arm {
    Param ([String] $name, [String] $arm, [String] $configPath)

    $armPath = Split-Path -Path $configPath -Parent
    $armStopwatch = [System.Diagnostics.Stopwatch]::startNew()

    $row = [ordered]@{
        "Arm"                  = $name
        "Engine settings"      = Format-Settings -settings $armSettings[$arm]
        "Chat decode tok/s"    = "-"
        "16K prompt tok/s"     = "-"
        "Agent decode tok/s"   = "-"
        "Agent cache hit %"    = "-"
        "Minutes"              = "-"
        "Status"               = "ok"
    }

    Write-Host "Arm ${name}: starting..." -ForegroundColor "Yellow"

    $process = $null
    $logLengths = Get-EngineLogLengths

    try {
        Assert-GpuFree

        $process = Start-ArmServer -configPath $configPath -armPath $armPath

        if (!(Wait-Server -process $process)) {
            throw "the server did not load, see server.log, server.err.log and engine.log"
        }

        Invoke-Smoke

        $benchPath = Join-Path $armPath "bench"

        # Out-Host: its output would otherwise become this function's return value.
        & $benchmarkScript -url $url -out $benchPath -arguments @("--runs", "${runs}") | Out-Host

        $resultsPath = Get-ChildItem -Path $benchPath -Filter "results.json" -Recurse -File |
            Sort-Object -Property "LastWriteTime" -Descending |
            Select-Object -First 1 -ExpandProperty "FullName"

        $results = (Get-Content -Raw -Path $resultsPath | ConvertFrom-Json).results

        $row["Chat decode tok/s"] = Format-Value -value $results.chat.decode_tps.median -format "0.0"
        $row["16K prompt tok/s"] = Format-Value -value $results.prompts."16K".prompt_tps.median -format "0"
        $row["Agent decode tok/s"] = Format-Value -value $results.agent.turn_decode_tps.median -format "0.0"
        $row["Agent cache hit %"] = Format-Value -value $results.agent.hit_pct.median -format "0.0"
    } catch {
        $row["Status"] = "failed: $($_.Exception.Message -replace '[\r\n|]+', ' ')"
        Write-Host "Arm ${name} failed: $($_.Exception.Message)" -ForegroundColor "Red"
    } finally {
        Stop-ArmServer -process $process
        Copy-EngineLog -before $logLengths -armPath $armPath
    }

    $row["Minutes"] = Format-Value -value $armStopwatch.Elapsed.TotalMinutes -format "0"
    $row
}

if (-not (Test-Path -Path $basalt)) {
    throw "vendor\basalt\bin\basalt.exe is missing. Run .\update_basalt.ps1 first."
}

if (!$tier) {
    $tiers = @(Get-ChildItem -Path $presetsPath -Filter "*.json" -File)

    if ($tiers.Count -ne 1) {
        throw "Name the tier with -tier: $(($tiers | ForEach-Object { $_.BaseName }) -join ', ')"
    }

    $tier = $tiers[0].BaseName
}

$tierPath = Join-Path $presetsPath "${tier}.json"

if (-not (Test-Path -Path $tierPath)) {
    throw "No tier file '${tierPath}'."
}

if (($arms -contains "custom") -and !$custom.Count) {
    throw "The arm custom needs its engine settings: -custom @{ `"name`" = value }."
}

$alias = (Get-Content -Raw -Path $tierPath | ConvertFrom-Json).server.alias
$engineFlags = @(& $basalt --help 2>&1 | ForEach-Object { [regex]::Matches("$_", "--[a-z0-9-]+") } | ForEach-Object { $_.Value })

$runPath = Join-Path $PSScriptRoot ".tmp\bench\experiment-$(Get-Date -Format 'yyyy-MM-dd_HHmm')"
$selected = @($armOrder | Where-Object { $arms -contains $_ })

# The baseline also runs last, to show how far the numbers drift.
$runOrder = [System.Collections.Generic.List[object]]::new()

foreach ($arm in $selected) {
    $runOrder.Add(@{ name = $arm; arm = $arm })
}

if (($selected -contains "baseline") -and $selected.Count -gt 1) {
    $runOrder.Add(@{ name = "baseline-end"; arm = "baseline" })
}

foreach ($entry in $runOrder) {
    $armPath = Join-Path $runPath $entry.name
    New-Item -Path $armPath -ItemType "directory" -Force | Out-Null
    $entry.config = New-ArmConfig -arm $entry.arm -armPath $armPath
    Test-ArmConfig -configPath $entry.config
}

Write-Host "Configs: ${runPath}" -ForegroundColor "DarkYellow"
Write-Host "Arms: $(($runOrder | ForEach-Object { $_.name }) -join ', ')" -ForegroundColor "DarkYellow"

if ($check) {
    Write-Host "The configs are fine. No server was started." -ForegroundColor "Yellow"
    exit
}

$owner = Get-PortOwner

if ($owner) {
    $commandLine = (Get-CimInstance -ClassName "Win32_Process" -Filter "ProcessId = ${owner}").CommandLine
    throw "Port ${port} is taken by PID ${owner}: ${commandLine}`nIt may have clients, so this script does not stop it."
}

$commit = git -C $basaltPath rev-parse --short=8 HEAD
$driver = nvidia-smi --id=0 --query-gpu=driver_version --format=csv,noheader

$rows = [System.Collections.Generic.List[object]]::new()

try {
    foreach ($entry in $runOrder) {
        $rows.Add((Invoke-Arm -name $entry.name -arm $entry.arm -configPath $entry.config))
    }
} finally {
    if ($rows.Count) {
        $table = Format-MarkdownTable -rows $rows
        $summary = "# Experiment ${tier}`n`nBasalt ${commit}, driver ${driver}, ${runs} runs, $(Get-Date -Format 'yyyy-MM-dd HH:mm').`n`n${table}`n"
        Set-Content -Path (Join-Path $runPath "summary.md") -Value $summary -Encoding "utf8"
        Write-Host $table
    }
}

$stopwatch.Stop()
$durationInMinutes = [Math]::Floor($stopwatch.Elapsed.TotalMinutes)

Write-Host "Finished the experiment in ${durationInMinutes} minutes: $(Join-Path $runPath 'summary.md')" -ForegroundColor "Yellow"
