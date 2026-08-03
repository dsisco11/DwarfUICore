[CmdletBinding(PositionalBinding=$false)]
param(
    [Parameter(Position=0, ValueFromRemainingArguments)]
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

$resolvedEnvFile = Join-Path $projectRoot '.env'
Import-EnvironmentFile -Path $resolvedEnvFile -AllowMissing

$DFHackRunner = [Environment]::GetEnvironmentVariable(
    'DFHACK_RUNNER', 'Process')
$DFHackRoot = [Environment]::GetEnvironmentVariable(
    'DFHACK_ROOT', 'Process')
$resolvedRunner = Resolve-DFHackRunner -RunnerPath $DFHackRunner `
    -DFHackRoot $DFHackRoot
$env:DFHACK_RUNNER = $resolvedRunner

& dwarfspec run @DwarfSpecArgs
exit $LASTEXITCODE
