[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]] $BustedArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$localBustedRunner = Join-Path $projectRoot 'lua_modules\bin\busted.bat'
$bustedConfig = Join-Path $projectRoot '.busted'

$bustedRunner = if (Test-Path -LiteralPath $localBustedRunner -PathType Leaf) {
    $localBustedRunner
} else {
    $globalBusted = Get-Command 'busted' -ErrorAction SilentlyContinue
    if ($globalBusted) { $globalBusted.Source } else { $null }
}

if (-not $bustedRunner) {
    throw "Busted was not found in the project-local LuaRocks tree or on PATH. Provision the pinned test dependencies with LuaRocks before running tests; this entrypoint does not install, update, or repair dependencies."
}

if (-not (Test-Path -LiteralPath $bustedConfig -PathType Leaf)) {
    throw "Repository Busted configuration was not found at '$bustedConfig'."
}

& (Join-Path $PSScriptRoot 'Check-UnitTestNaming.ps1')

Push-Location $projectRoot
try {
    & $bustedRunner '--config-file' $bustedConfig @BustedArgs
    $bustedExitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

exit $bustedExitCode
