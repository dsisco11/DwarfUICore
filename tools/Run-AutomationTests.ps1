[CmdletBinding()]
param(
    [string] $DFHackRunner = $env:DFHACK_RUNNER,
    [string] $DFHackRoot = $env:DFHACK_ROOT,
    [string] $EnvFile = '.env.local',
    [Parameter(ValueFromRemainingArguments)]
    [string[]] $DwarfSpecArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$commonTools = Join-Path $PSScriptRoot 'Common.ps1'
if (-not (Test-Path -LiteralPath $commonTools -PathType Leaf)) {
    throw "Missing required common tools: $commonTools"
}
. $commonTools

$resolvedEnvFile = $EnvFile
if (-not [IO.Path]::IsPathRooted($resolvedEnvFile)) {
    $resolvedEnvFile = Join-Path $projectRoot $resolvedEnvFile
}
Import-EnvironmentFile -Path $resolvedEnvFile -AllowMissing

if (-not $DFHackRunner) {
    $DFHackRunner = [Environment]::GetEnvironmentVariable(
        'DFHACK_RUNNER', 'Process')
}
if (-not $DFHackRoot) {
    $DFHackRoot = [Environment]::GetEnvironmentVariable(
        'DFHACK_ROOT', 'Process')
}
$resolvedRunner = Resolve-DFHackRunner -RunnerPath $DFHackRunner `
    -DFHackRoot $DFHackRoot
$env:DFHACK_RUNNER = $resolvedRunner

& dwarfspec run @DwarfSpecArgs
exit $LASTEXITCODE
