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
    [string] $RunId,
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
Extracts one machine-readable automation summary from runner output.
#>
function ConvertFrom-AutomationSummary {
    param(
        [Parameter(Mandatory)]
        [string[]] $Output
    )

    $line = $Output | Where-Object {
        $_ -match '^DWARFUI_AUTOMATION\s'
    } | Select-Object -Last 1
    if (-not $line) {
        throw 'DFHack output did not contain an automation summary.'
    }

    $fields = @{}
    foreach ($match in [regex]::Matches($line, '(\w+)=([^\s]+)')) {
        $fields[$match.Groups[1].Value] = $match.Groups[2].Value
    }
    if (-not $fields.ContainsKey('state')) {
        throw "Automation summary has no state: $line"
    }
    return [pscustomobject]@{
        Line = $line
        State = $fields.state
        OutputCount = if ($fields.ContainsKey('output_count')) {
            [int]$fields.output_count
        } else {
            0
        }
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

$dependencyFiles = @(
    '.luarocks\share\lua\5.4\busted\core.lua',
    '.luarocks\share\lua\5.4\busted\init.lua',
    '.luarocks\share\lua\5.4\luassert\init.lua',
    'Tests\Automation\support\system_adapter.lua',
    'Tests\Automation\support\lfs_adapter.lua'
)
foreach ($relativePath in $dependencyFiles) {
    $path = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing live automation dependency: $path"
    }
}

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
$bootstrapFile = Join-Path $repoRoot 'Tests\Automation\bootstrap.lua'
$statusFile = Join-Path $repoRoot 'Tests\Automation\status.lua'
$abortFile = Join-Path $repoRoot 'Tests\Automation\abort.lua'
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
if ($Spec) { $bootstrapArguments.Add("--spec=$Spec") }

$started = $false
$finished = $false
$outputOffset = 0
$finalState = $null
$stopwatch = [Diagnostics.Stopwatch]::StartNew()

try {
    $startResult = Invoke-DFHackRunner -Runner $runner `
        -Arguments $bootstrapArguments.ToArray()
    $startSummary = ConvertFrom-AutomationSummary $startResult.Output
    $started = $true
    $finalState = $startSummary.State

    while ($finalState -notin @('passed', 'failed', 'aborted')) {
        if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
            throw "Automation run timed out after $TimeoutSeconds seconds."
        }
        Start-Sleep -Milliseconds $PollIntervalMilliseconds
        $statusResult = Invoke-DFHackRunner -Runner $runner -Arguments @(
            'lua', '-f', $statusPath, $RunId, $outputOffset.ToString())
        $summary = ConvertFrom-AutomationSummary $statusResult.Output
        $outputOffset = $summary.OutputCount
        $finalState = $summary.State
    }

    $finished = $true
    if ($finalState -ne 'passed') {
        throw "Automation run finished with state '$finalState'."
    }
}
finally {
    if ($started -and -not $finished) {
        Invoke-DFHackRunner -Runner $runner -Arguments @(
            'lua', '-f', $abortPath, $RunId) -AllowFailure | Out-Null
    }
}
