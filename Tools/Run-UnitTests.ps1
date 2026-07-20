[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments)]
    [string[]] $BustedArgs
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$rockTree = Join-Path $projectRoot '.luarocks'
$bustedVersion = '2.3.0-1'
$luaSystemVersion = '0.3.0-2'
$testFileEnvironmentVariable = 'LUA_TEST_FILES'

if (-not (Get-Command luarocks -ErrorAction SilentlyContinue)) {
    throw 'LuaRocks was not found on PATH.'
}

$luaVersion = & lua -e "io.write(_VERSION:match('(%d+%.%d+)'))"
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($luaVersion)) {
    throw 'Could not determine the Lua version.'
}

& luarocks show luasystem $luaSystemVersion --tree $rockTree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing LuaSystem $luaSystemVersion into .luarocks..."
    & luarocks install luasystem $luaSystemVersion --tree $rockTree
    if ($LASTEXITCODE -ne 0) {
        throw "LuaRocks failed to install LuaSystem $luaSystemVersion."
    }
}

& luarocks show busted $bustedVersion --tree $rockTree *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Installing Busted $bustedVersion into .luarocks..."
    & luarocks install busted $bustedVersion --tree $rockTree
    if ($LASTEXITCODE -ne 0) {
        throw "LuaRocks failed to install Busted $bustedVersion."
    }
}

$testsRoot = Join-Path $projectRoot 'tests'
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
$oldLuaCPath = [Environment]::GetEnvironmentVariable('LUA_CPATH', 'Process')
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
    $luaCPathEntries = @((Join-Path $rockTree "lib\lua\$luaVersion\?.dll"))
    if ($null -ne $oldLuaCPath) {
        $luaCPathEntries += $oldLuaCPath
    }
    Set-Item -LiteralPath Env:LUA_CPATH -Value ($luaCPathEntries -join ';')

    # The Busted helper validates this newline-delimited discovered suite list.
    # Keeping the contract project-neutral lets the runner be reused elsewhere.
    Set-Item -LiteralPath "Env:$testFileEnvironmentVariable" -Value ($testFiles -join "`n")

    $bustedLauncher = Join-Path $rockTree 'bin\busted'
    if (-not (Test-Path -LiteralPath $bustedLauncher -PathType Leaf)) {
        throw "Busted launcher was not installed at $bustedLauncher"
    }
    $helper = Join-Path $testsRoot 'run.lua'
    & lua $bustedLauncher --helper $helper @BustedArgs @testFiles
    $testExitCode = $LASTEXITCODE
}
finally {
    Restore-ProcessEnvironmentVariable -Name 'LUA_PATH' -Value $oldLuaPath
    Restore-ProcessEnvironmentVariable -Name 'LUA_CPATH' -Value $oldLuaCPath
    Restore-ProcessEnvironmentVariable -Name $testFileEnvironmentVariable -Value $oldTestFiles
}

if ($testExitCode -ne 0) {
    throw "Busted tests failed with exit code $testExitCode."
}
