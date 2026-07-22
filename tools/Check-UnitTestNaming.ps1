[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$testsRoot = Join-Path $projectRoot 'tests'
$excludedRoots = @(
    (Join-Path $testsRoot 'live'),
    (Join-Path $testsRoot 'support'),
    (Join-Path $testsRoot 'dwarfspec'),
    (Join-Path $testsRoot 'fixtures')
)

$invalidFiles = Get-ChildItem -LiteralPath $testsRoot -Recurse -File |
    Where-Object {
        $path = $_.FullName
        $isExcluded = $false
        foreach ($excludedRoot in $excludedRoots) {
            if ($path.StartsWith($excludedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
                $isExcluded = $true
                break
            }
        }
        if (-not $isExcluded -and $path -match '[\\/]support[\\/]') {
            $isExcluded = $true
        }
        -not $isExcluded -and $_.Name -ne 'run.lua' -and
            $_.Extension -eq '.lua' -and
            $_.Name -notlike '*.spec.lua' -and $_.Name -notlike '*.ds.lua'
    }

if ($invalidFiles) {
    $names = $invalidFiles.FullName | ForEach-Object {
        $_.Substring($projectRoot.Length + 1)
    }
    throw "Standalone unit-test files must end in '.spec.lua' (DwarfSpec files use '.ds.lua'): $($names -join ', ')"
}
