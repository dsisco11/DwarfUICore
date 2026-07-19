[CmdletBinding()]
param(
    [string] $LuaCompiler = $env:DFHACK_LUAC,
    [string] $RequiredLuaVersion = $env:DFHACK_LUA_VERSION,
    [bool] $LiveReload = $true,
    [string] $SourceDir = 'src',
    [string] $DFHackRunner = $env:DFHACK_RUNNER,
    [string] $DwarfFortressRoot = $env:DWARF_FORTRESS_ROOT,
    [string] $ReloadOutputPath,
    [string] $EnvFile = '.env.local'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $PSScriptRoot
$syntaxCheck = Join-Path $PSScriptRoot 'Check-LuaSyntax.ps1'
$commonTools = Join-Path $PSScriptRoot 'Common.ps1'

if (-not (Test-Path -LiteralPath $commonTools -PathType Leaf)) {
    throw "Missing required common tools: $commonTools"
}
. $commonTools

$resolvedEnvFile = $EnvFile
if (-not [IO.Path]::IsPathRooted($resolvedEnvFile)) {
    $resolvedEnvFile = Join-Path $scriptRoot $resolvedEnvFile
}
Import-EnvironmentFile -Path $resolvedEnvFile -AllowMissing

$processLuaCompiler = [Environment]::GetEnvironmentVariable('DFHACK_LUAC', 'Process')
$processRequiredLuaVersion = [Environment]::GetEnvironmentVariable('DFHACK_LUA_VERSION', 'Process')
$processDFHackRunner = [Environment]::GetEnvironmentVariable('DFHACK_RUNNER', 'Process')
$processDwarfFortressRoot = [Environment]::GetEnvironmentVariable('DWARF_FORTRESS_ROOT', 'Process')

if (-not $LuaCompiler) {
    $LuaCompiler = if ($processLuaCompiler) {
        $processLuaCompiler
    } else {
        'luac.exe'
    }
}
if (-not $RequiredLuaVersion) {
    $RequiredLuaVersion = $processRequiredLuaVersion
}
if (-not $DFHackRunner) {
    $DFHackRunner = $processDFHackRunner
}
if (-not $DwarfFortressRoot) {
    $DwarfFortressRoot = $processDwarfFortressRoot
}

if (-not (Test-Path -LiteralPath $syntaxCheck -PathType Leaf)) {
    throw "Missing required syntax checker: $syntaxCheck"
}

$sourcePath = if ([IO.Path]::IsPathRooted($SourceDir)) {
    $SourceDir
} else {
    Join-Path $scriptRoot $SourceDir
}

& $syntaxCheck -LuaCompiler $LuaCompiler -RequiredLuaVersion $RequiredLuaVersion `
    -SourceDir $sourcePath -IncludeTests
if ($LASTEXITCODE -ne 0) {
    throw 'Lua syntax check failed.'
}

if ($LiveReload) {
    $sourcePath = (Resolve-Path -LiteralPath $sourcePath).Path
    $modInfo = Get-ModInfo -InfoPath (Join-Path $sourcePath 'info.txt')
    if (-not $modInfo.Id) {
        throw "Missing required [ID] in $(Join-Path $sourcePath 'info.txt')"
    }

    $runner = Resolve-DFHackRunner -RunnerPath $DFHackRunner `
        -DwarfFortressRoot $DwarfFortressRoot
    Write-Host "Running DFHack command: $($modInfo.Id) reload"
    $reloadOutput = @(& $runner $modInfo.Id reload 2>&1) |
        ForEach-Object { $_.ToString() }
    $reloadExitCode = $LASTEXITCODE

    foreach ($line in $reloadOutput) {
        Write-Host $line
    }

    if ($ReloadOutputPath) {
        $resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
            $ReloadOutputPath)
        $outputDirectory = Split-Path -Parent $resolvedOutputPath
        if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
            New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
        }
        $reloadOutput | Out-File -LiteralPath $resolvedOutputPath -Encoding utf8
        Write-Host "Captured DFHack output in $resolvedOutputPath"
    }

    if ($reloadExitCode -ne 0) {
        throw "DFHack command '$($modInfo.Id) reload' failed with exit code $reloadExitCode."
    }
}
