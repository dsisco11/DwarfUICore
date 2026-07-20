[CmdletBinding()]
param(
    [string] $LuaCompiler = $env:LUA_COMPILER,
    [string] $RequiredLuaVersion = $env:LUA_REQUIRED_VERSION,
    [string] $SourceDir = 'src',
    [string] $testsDir = 'tests',
    [switch] $Includetests
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $LuaCompiler) {
    $LuaCompiler = 'luac.exe'
}

$compiler = Get-Command $LuaCompiler -ErrorAction SilentlyContinue
if (-not $compiler) {
    throw "Lua compiler was not found: $LuaCompiler. Install luac.exe on PATH, set LUA_COMPILER, or pass -LuaCompiler."
}

$version = (& $compiler.Source -v 2>&1 | Out-String)
if ($RequiredLuaVersion -and $version -notmatch "Lua $([regex]::Escape($RequiredLuaVersion))") {
    throw "Expected a Lua $RequiredLuaVersion compiler; got: $version"
}
$versionMatch = [regex]::Match($version, 'Lua ([0-9]+(?:\.[0-9]+)+)')
$compilerVersion = if ($versionMatch.Success) {
    $versionMatch.Groups[1].Value
} else {
    'unknown version'
}

$projectRoot = Split-Path -Parent $PSScriptRoot

function Resolve-ProjectDirectory {
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Label,

        [switch] $AllowMissing
    )

    $candidate = if ([IO.Path]::IsPathRooted($Path)) {
        $Path
    } else {
        Join-Path $projectRoot $Path
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        if ($AllowMissing) {
            return $null
        }
        throw "Could not find $Label directory: $candidate"
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

$sourcePath = Resolve-ProjectDirectory -Path $SourceDir -Label 'Lua source'
$testPath = if ($Includetests) {
    Resolve-ProjectDirectory -Path $testsDir -Label 'Lua test' -AllowMissing
}

$productionFiles = @(Get-ChildItem -LiteralPath $sourcePath -Recurse -File -Filter '*.lua' |
    Sort-Object FullName)
$testFiles = @(
    if ($testPath) {
        Get-ChildItem -LiteralPath $testPath -Recurse -File -Filter '*.lua' |
            Sort-Object FullName
    }
)
$luaFiles = @($productionFiles + $testFiles)

foreach ($luaFile in $luaFiles) {
    & $compiler.Source -p $luaFile.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "Lua syntax check failed: $($luaFile.FullName)"
    }
}

Write-Host "Lua $compilerVersion syntax check passed for $($productionFiles.Count) production file(s) and $($testFiles.Count) test/support file(s)."
