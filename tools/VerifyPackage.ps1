[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $SourceDir,
    [Parameter(Mandatory)]
    [string] $ZipPath,
    [Parameter(Mandatory)]
    [string] $ExpandedPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Get-Manifest {
    param([Parameter(Mandatory)][string] $Root)

    $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
    return @(
        Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File -Force | ForEach-Object {
            [pscustomobject]@{
                RelativePath = [IO.Path]::GetRelativePath($resolvedRoot, $_.FullName).Replace('\', '/')
                Hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            }
        } | Sort-Object RelativePath
    )
}

function Assert-MatchesSource {
    param(
        [Parameter(Mandatory)][object[]] $Expected,
        [Parameter(Mandatory)][object[]] $Actual,
        [Parameter(Mandatory)][string] $Label
    )

    $expectedMap = @{}
    $actualMap = @{}
    foreach ($entry in $Expected) { $expectedMap[$entry.RelativePath] = $entry.Hash }
    foreach ($entry in $Actual) { $actualMap[$entry.RelativePath] = $entry.Hash }

    $missing = @($expectedMap.Keys | Where-Object {
        -not $actualMap.ContainsKey($_)
    } | Sort-Object)
    $unexpected = @($actualMap.Keys | Where-Object {
        -not $expectedMap.ContainsKey($_)
    } | Sort-Object)
    if ($missing.Count -gt 0 -or $unexpected.Count -gt 0) {
        $details = @()
        if ($missing.Count -gt 0) {
            $details += "missing: $($missing -join ', ')"
        }
        if ($unexpected.Count -gt 0) {
            $details += "unexpected: $($unexpected -join ', ')"
        }
        throw "$Label file manifest differs from source ($($details -join '; '))."
    }

    $differing = @($expectedMap.Keys | Where-Object {
        $expectedMap[$_] -ne $actualMap[$_]
    } | Sort-Object)
    if ($differing.Count -gt 0) {
        throw "$Label file content differs from source (differing: $($differing -join ', '))."
    }
}

$scriptRoot = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptRoot '..')).Path

function Resolve-RepositoryPath {
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string] $PathType
    )

    $candidate = if ([IO.Path]::IsPathFullyQualified($Path)) {
        $Path
    } else {
        Join-Path $repoRoot $Path
    }
    $resolved = Resolve-Path -LiteralPath $candidate
    if (-not (Test-Path -LiteralPath $resolved.Path -PathType $PathType)) {
        throw "Expected a $PathType path: $candidate"
    }
    return $resolved.Path
}

$sourcePath = Resolve-RepositoryPath -Path $SourceDir -PathType Container
$zipFilePath = Resolve-RepositoryPath -Path $ZipPath -PathType Leaf
$expandedDirectoryPath = Resolve-RepositoryPath `
    -Path $ExpandedPath -PathType Container

$sourceManifest = Get-Manifest -Root $sourcePath
if (-not ($sourceManifest.RelativePath -contains 'info.txt')) {
    throw 'Source must contain info.txt at its root.'
}
if (-not ($sourceManifest.RelativePath | Where-Object { $_ -like 'scripts_modinstalled/*' })) {
    throw 'Source must contain at least one file under scripts_modinstalled/.'
}

Assert-MatchesSource -Expected $sourceManifest `
    -Actual (Get-Manifest -Root $expandedDirectoryPath) `
    -Label 'Expanded package'
Write-Host 'Expanded package verification passed.'

$extractRoot = Join-Path ([IO.Path]::GetTempPath()) "DFHackModVerify-$([guid]::NewGuid())"
try {
    Expand-Archive -LiteralPath $zipFilePath -DestinationPath $extractRoot
    Assert-MatchesSource -Expected $sourceManifest `
        -Actual (Get-Manifest -Root $extractRoot) `
        -Label 'Zip package'
    Write-Host 'Zip package verification passed.'
}
finally {
    if (Test-Path -LiteralPath $extractRoot) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force
    }
}

Write-Host 'All package verification passed.'
