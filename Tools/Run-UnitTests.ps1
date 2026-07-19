[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]] $LuaUnitArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$rockTree = Join-Path $projectRoot '.luarocks'
$luaUnitVersion = '3.5-1'
$testFileEnvironmentVariable = 'DFHACK_LUA_TEST_FILES'

if (-not (Get-Command luarocks -ErrorAction SilentlyContinue)) {
    throw 'LuaRocks was not found on PATH.'
}

$luaVersion = & lua -e "io.write(_VERSION:match('(%d+%.%d+)'))"
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($luaVersion)) {
    throw 'Could not determine the Lua version.'
}

& luarocks show luaunit $luaUnitVersion --tree $rockTree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing LuaUnit $luaUnitVersion into .luarocks..."
    & luarocks install luaunit $luaUnitVersion --tree $rockTree
    if ($LASTEXITCODE -ne 0) {
        throw "LuaRocks failed to install LuaUnit $luaUnitVersion."
    }
}

$testsRoot = Join-Path $projectRoot 'Tests'
if (-not (Test-Path -LiteralPath $testsRoot -PathType Container)) {
    throw "Could not find Lua test directory: $testsRoot"
}

$testFiles = @(
    Get-ChildItem -LiteralPath $testsRoot -Recurse -File -Filter '*.lua' |
        Where-Object {
            $_.Name -match '(^test_.*|.*_test)\.lua$'
        } |
        Sort-Object FullName |
        ForEach-Object FullName
)

if ($testFiles.Count -eq 0) {
    throw 'No Lua test files found. Name tests test_*.lua or *_test.lua.'
}

$oldLuaPath = [Environment]::GetEnvironmentVariable('LUA_PATH', 'Process')
$oldTestFiles = [Environment]::GetEnvironmentVariable($testFileEnvironmentVariable, 'Process')

function Restore-ProcessEnvironmentVariable {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [string] $Value
    )

    if ($null -eq $Value) {
        Remove-Item -LiteralPath "Env:$Name" -ErrorAction SilentlyContinue
    } else {
        Set-Item -LiteralPath "Env:$Name" -Value $Value
    }
}

try {
    $rockLuaPath = @(
        (Join-Path $rockTree "share\lua\$luaVersion\?.lua"),
        (Join-Path $rockTree "share\lua\$luaVersion\?\init.lua")
    ) -join ';'
    $testLuaPath = @(
        (Join-Path $testsRoot '?.lua'),
        (Join-Path $testsRoot '?\init.lua')
    ) -join ';'
    $productionRoot = Join-Path $projectRoot 'src\scripts_modinstalled'
    $productionLuaPath = @(
        (Join-Path $productionRoot '?.lua'),
        (Join-Path $productionRoot '?\init.lua')
    ) -join ';'
    $luaPathEntries = @($rockLuaPath, $testLuaPath, $productionLuaPath)
    if ($null -ne $oldLuaPath) {
        $luaPathEntries += $oldLuaPath
    }
    Set-Item -LiteralPath Env:LUA_PATH -Value ($luaPathEntries -join ';')
    # Tests/run.lua consumes this newline-delimited discovered suite list. Keeping
    # the contract DFHack-neutral lets the runner be reused by other Lua projects.
    Set-Item -LiteralPath "Env:$testFileEnvironmentVariable" -Value ($testFiles -join "`n")

    & lua (Join-Path $projectRoot 'Tests/run.lua') @LuaUnitArgs
    $testExitCode = $LASTEXITCODE
}
finally {
    Restore-ProcessEnvironmentVariable -Name 'LUA_PATH' -Value $oldLuaPath
    Restore-ProcessEnvironmentVariable -Name $testFileEnvironmentVariable -Value $oldTestFiles
}

if ($testExitCode -ne 0) {
    throw "LuaUnit tests failed with exit code $testExitCode."
}
