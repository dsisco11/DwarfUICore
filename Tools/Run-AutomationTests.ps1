[CmdletBinding()]
param(
    [string[]] $Filter = @(),
    [string[]] $FilterOut = @(),
    [string[]] $Name = @(),
    [string[]] $Tag = @(),
    [string[]] $ExcludeTag = @(),
    [ValidateRange(1, 1000)]
    [int] $Repeat = 1,
    [string] $Spec,
    [ValidateRange(1, 3600)]
    [int] $TimeoutSeconds = 30,
    [ValidateRange(25, 5000)]
    [int] $PollIntervalMilliseconds = 100,
    [ValidateRange(1, 100000)]
    [int] $StartupDelayFrames = 1,
    [ValidateRange(100, 60000)]
    [int] $LeaseTimeoutMilliseconds = 5000,
    [ValidateRange(1, 100000)]
    [int] $LeaseCheckFrames = 30,
    [string] $RunId,
    [string] $OverlayFixture,
    [string] $DFHackRunner = $env:MOD_COMMAND_RUNNER,
    [string] $DwarfFortressRoot = $env:GAME_ROOT,
    [string] $EnvFile = '.env.local'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$commonTools = Join-Path $PSScriptRoot 'Common.ps1'
if (-not (Test-Path -LiteralPath $commonTools -PathType Leaf)) {
    throw "Missing required common tools: $commonTools"
}
. $commonTools

<#
.SYNOPSIS
Invokes dfhack-run and returns its combined output as stable strings.
#>
function Invoke-DFHackRunner {
    param(
        [Parameter(Mandatory)]
        [string] $Runner,

        [Parameter(Mandatory)]
        [string[]] $Arguments,

        [switch] $AllowFailure
    )

    $output = @(& $Runner @Arguments 2>&1) |
        ForEach-Object { $_.ToString() }
    $exitCode = $LASTEXITCODE
    foreach ($line in $output) { Write-Host $line }
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "dfhack-run failed with exit code $exitCode."
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

<#
.SYNOPSIS
Extracts one canonical JSON automation report from DFHack output.
#>
function ConvertFrom-AutomationReport {
    param(
        [Parameter(Mandatory)]
        [string[]] $Output
    )

    $line = $Output | Where-Object {
        $_ -match '^DWARFUI_AUTOMATION_JSON\s+'
    } | Select-Object -Last 1
    if (-not $line) {
        throw 'DFHack output did not contain an automation JSON report.'
    }
    $payload = $line.Substring('DWARFUI_AUTOMATION_JSON '.Length)
    try {
        $report = $payload | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "DFHack emitted invalid automation JSON: $($_.Exception.Message)"
    }
    foreach ($property in @(
            'protocol', 'run_id', 'state', 'terminal', 'generation', 'counts',
            'totals', 'output_count', 'cleanup_confirmed', 'failures')) {
        if ($null -eq $report.PSObject.Properties[$property]) {
            throw "Automation JSON report is missing '$property': $line"
        }
    }
    return [pscustomobject]@{
        Line = $line
        Protocol = [int]$report.protocol
        RunId = [string]$report.run_id
        State = [string]$report.state
        Terminal = [bool]$report.terminal
        CleanupConfirmed = [bool]$report.cleanup_confirmed
        OutputCount = [int]$report.output_count
        Report = $report
    }
}

<#
.SYNOPSIS
Validates that a DFHack JSON report belongs to the requested supported protocol run.
#>
function Assert-AutomationReport {
    param(
        [Parameter(Mandatory)]
        [object] $Summary,

        [Parameter(Mandatory)]
        [string] $ExpectedRunId
    )

    if ($Summary.Protocol -ne 1) {
        throw "Unsupported automation protocol '$($Summary.Protocol)' in: $($Summary.Line)"
    }
    if ($Summary.RunId -ne $ExpectedRunId) {
        throw "Automation report run id '$($Summary.RunId)' does not match '$ExpectedRunId'."
    }
}

<#
.SYNOPSIS
Installs the pinned pure-Lua Busted dependency only when it is absent.
#>
function Ensure-AutomationDependencies {
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot
    )

    $dependencyFiles = @(
        '.luarocks\share\lua\5.4\busted\core.lua',
        '.luarocks\share\lua\5.4\busted\init.lua',
        '.luarocks\share\lua\5.4\luassert\init.lua'
    )
    $missing = @($dependencyFiles | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $RepositoryRoot $_) -PathType Leaf)
    })
    if ($missing.Count -gt 0) {
        $luaRocks = Get-Command 'luarocks' -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if (-not $luaRocks) {
            throw 'Live automation dependencies are missing and LuaRocks was not found on PATH.'
        }
        $tree = Join-Path $RepositoryRoot '.luarocks'
        Write-Host 'Installing pinned Busted 2.3.0-1 sources for live automation...'
        & $luaRocks.Source install busted 2.3.0-1 --tree $tree
        if ($LASTEXITCODE -ne 0) {
            throw 'LuaRocks failed to install pinned Busted 2.3.0-1 sources.'
        }
        $missing = @($dependencyFiles | Where-Object {
            -not (Test-Path -LiteralPath (Join-Path $RepositoryRoot $_) -PathType Leaf)
        })
    }
    if ($missing.Count -gt 0) {
        throw ('Live automation dependency installation did not provide: ' +
            ($missing -join ', '))
    }

    foreach ($relativePath in @(
            'tests/automation\support\system_adapter.lua',
            'tests/automation\support\lfs_adapter.lua')) {
        $path = Join-Path $RepositoryRoot $relativePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Missing live automation adapter: $path"
        }
    }
}

<#
.SYNOPSIS
Stages one allowlisted overlay fixture under the game's GUI script directory.
#>
function New-OverlayFixtureStage {
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $GameRoot,

        [Parameter(Mandatory)]
        [string] $FixtureName,

        [Parameter(Mandatory)]
        [string] $AutomationRunId
    )

    if ($FixtureName -notmatch '^[a-z][a-z0-9_-]*$') {
        throw 'Overlay fixture names must be lowercase letters, digits, hyphens, or underscores.'
    }
    $source = Join-Path $RepositoryRoot "tests/automation\overlay_fixtures\$FixtureName.lua"
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Approved overlay fixture was not found: $source"
    }
    $destinationDirectory = Join-Path $GameRoot 'hack\scripts\gui'
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        throw "DFHack GUI script directory was not found: $destinationDirectory"
    }
    $leaf = "dwarfui_automation_$AutomationRunId`_$FixtureName.lua"
    $destination = Join-Path $destinationDirectory $leaf
    $resolvedDirectory = (Resolve-Path -LiteralPath $destinationDirectory).Path
    if ([IO.Path]::GetDirectoryName($destination) -ne $resolvedDirectory -or
            [IO.Path]::GetFileName($destination) -ne $leaf) {
        throw 'Refusing to stage an overlay fixture outside the exact GUI script directory.'
    }
    if (Test-Path -LiteralPath $destination) {
        throw "Refusing to overwrite existing overlay fixture staging path: $destination"
    }
    Copy-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
    return [pscustomobject]@{
        Path = $destination
        Directory = $resolvedDirectory
    }
}

<#
.SYNOPSIS
Removes only the exact overlay fixture file created for this automation run.
#>
function Remove-OverlayFixtureStage {
    param(
        [AllowNull()]
        [object] $Stage
    )

    if ($null -eq $Stage) { return }
    if ([IO.Path]::GetDirectoryName($Stage.Path) -ne $Stage.Directory -or
            [IO.Path]::GetFileName($Stage.Path) -notmatch '^dwarfui_automation_.*\.lua$') {
        throw "Refusing to remove an unexpected overlay fixture path: $($Stage.Path)"
    }
    if (Test-Path -LiteralPath $Stage.Path -PathType Leaf) {
        Remove-Item -LiteralPath $Stage.Path -Force -ErrorAction Stop
    }
}

<#
.SYNOPSIS
Rescans DFHack overlays and requires an explicit in-process success marker.
#>
function Invoke-OverlayFixtureRescan {
    param(
        [Parameter(Mandatory)]
        [string] $Runner
    )

    $result = Invoke-DFHackRunner -Runner $Runner -Arguments @(
        'lua', '!(function() require("plugins.overlay").rescan(); return "DWARFUI_OVERLAY_RESCAN_OK" end)()') `
        -AllowFailure
    if ($result.ExitCode -ne 0 -or
            $result.Output -notcontains 'DWARFUI_OVERLAY_RESCAN_OK' -or
            $result.Output -match 'error loading overlay widget|stack traceback:') {
        throw 'DFHack overlay rescan did not report success.'
    }
}

<#
.SYNOPSIS
Adds repeated string options to the bootstrap argument list.
#>
function Add-AutomationOptions {
    param(
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[string]] $Arguments,

        [Parameter(Mandatory)]
        [string] $OptionName,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $Values
    )

    foreach ($value in $Values) {
        $Arguments.Add("--$OptionName=$value")
    }
}

$resolvedEnvFile = $EnvFile
if (-not [IO.Path]::IsPathRooted($resolvedEnvFile)) {
    $resolvedEnvFile = Join-Path $repoRoot $resolvedEnvFile
}
Import-EnvironmentFile -Path $resolvedEnvFile -AllowMissing

if (-not $DFHackRunner) {
    $DFHackRunner = [Environment]::GetEnvironmentVariable(
        'MOD_COMMAND_RUNNER', 'Process')
}
if (-not $DwarfFortressRoot) {
    $DwarfFortressRoot = [Environment]::GetEnvironmentVariable(
        'GAME_ROOT', 'Process')
}
$runner = Resolve-DFHackRunner -RunnerPath $DFHackRunner `
    -DwarfFortressRoot $DwarfFortressRoot

Ensure-AutomationDependencies -RepositoryRoot $repoRoot

$contextProbe = Invoke-DFHackRunner -Runner $runner -Arguments @(
    'lua',
    '!table.concat({tostring(dfhack.is_core_context),type(dfhack.timeout)},",")'
)
if (($contextProbe.Output | Select-Object -Last 1) -ne 'true,function') {
    throw 'DFHack command execution is not using a healthy core Lua context.'
}

if (-not $RunId) {
    $RunId = 'dwarfui-' + [guid]::NewGuid().ToString('N')
}
if ($RunId -notmatch '^[A-Za-z0-9_.-]+$') {
    throw 'RunId must contain only letters, digits, dot, underscore, or dash.'
}
$bootstrapFile = Join-Path $repoRoot 'tests/automation\bootstrap.lua'
$statusFile = Join-Path $repoRoot 'tests/automation\status.lua'
$abortFile = Join-Path $repoRoot 'tests/automation\abort.lua'
$bootstrapPath = (Resolve-Path -LiteralPath $bootstrapFile).Path.Replace('\', '/')
$statusPath = (Resolve-Path -LiteralPath $statusFile).Path.Replace('\', '/')
$abortPath = (Resolve-Path -LiteralPath $abortFile).Path.Replace('\', '/')

$bootstrapArguments = [System.Collections.Generic.List[string]]::new()
$bootstrapArguments.Add('lua')
$bootstrapArguments.Add('-f')
$bootstrapArguments.Add($bootstrapPath)
$bootstrapArguments.Add($RunId)
Add-AutomationOptions $bootstrapArguments 'filter' $Filter
Add-AutomationOptions $bootstrapArguments 'filter-out' $FilterOut
Add-AutomationOptions $bootstrapArguments 'name' $Name
Add-AutomationOptions $bootstrapArguments 'tag' $Tag
Add-AutomationOptions $bootstrapArguments 'exclude-tag' $ExcludeTag
$bootstrapArguments.Add("--repeat=$Repeat")
$bootstrapArguments.Add("--defer-frames=$StartupDelayFrames")
$bootstrapArguments.Add("--lease-timeout-ms=$LeaseTimeoutMilliseconds")
$bootstrapArguments.Add("--lease-check-frames=$LeaseCheckFrames")
if ($Spec) { $bootstrapArguments.Add("--spec=$Spec") }

$started = $false
$finished = $false
$outputOffset = 0
$finalState = $null
$cleanupConfirmed = $false
$overlayStage = $null
$stopwatch = [Diagnostics.Stopwatch]::StartNew()

try {
    if ($OverlayFixture) {
        if (-not $DwarfFortressRoot) {
            throw 'Overlay fixture staging requires -DwarfFortressRoot or GAME_ROOT.'
        }
        $overlayStage = New-OverlayFixtureStage -RepositoryRoot $repoRoot `
            -GameRoot $DwarfFortressRoot -FixtureName $OverlayFixture `
            -AutomationRunId $RunId
        Invoke-OverlayFixtureRescan -Runner $runner
    }
    $startResult = Invoke-DFHackRunner -Runner $runner `
        -Arguments $bootstrapArguments.ToArray()
    $startSummary = ConvertFrom-AutomationReport $startResult.Output
    Assert-AutomationReport -Summary $startSummary -ExpectedRunId $RunId
    $started = $true
    $finalState = $startSummary.State

    while ($finalState -notin @('passed', 'failed', 'aborted')) {
        if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            throw "Automation run timed out after $TimeoutSeconds seconds."
        }
        Start-Sleep -Milliseconds $PollIntervalMilliseconds
        $statusResult = Invoke-DFHackRunner -Runner $runner -Arguments @(
            'lua', '-f', $statusPath, $RunId, $outputOffset.ToString())
        $summary = ConvertFrom-AutomationReport $statusResult.Output
        Assert-AutomationReport -Summary $summary -ExpectedRunId $RunId
        $outputOffset = $summary.OutputCount
        $finalState = $summary.State
        $cleanupConfirmed = $summary.CleanupConfirmed
    }

    $finished = $true
    if ($finalState -ne 'passed') {
        throw "Automation run finished with state '$finalState'."
    }
    if (-not $cleanupConfirmed) {
        throw 'Automation run passed without confirmed live-state cleanup.'
    }
}
finally {
    if ($started -and -not $finished) {
        $abortResult = Invoke-DFHackRunner -Runner $runner -Arguments @(
            'lua', '-f', $abortPath, $RunId) -AllowFailure
        if ($abortResult.ExitCode -ne 0) {
            throw "Automation recovery abort command failed with exit code $($abortResult.ExitCode)."
        }
        $abortReport = ConvertFrom-AutomationReport $abortResult.Output
        Assert-AutomationReport -Summary $abortReport -ExpectedRunId $RunId
        if ($abortReport.State -ne 'aborted' -or -not $abortReport.CleanupConfirmed) {
            throw 'Automation recovery did not reach an aborted state with confirmed cleanup.'
        }
    }
    if ($overlayStage) {
        Remove-OverlayFixtureStage -Stage $overlayStage
        Invoke-OverlayFixtureRescan -Runner $runner
    }
}
