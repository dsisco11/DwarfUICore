[CmdletBinding()]
param(
    [string] $SourceDir = 'src',
    [string] $OutputDir = 'dist',
    [string] $PackageName = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function ConvertTo-SafeFileName {
    param([Parameter(Mandatory)][string] $Name)

    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $chars = $Name.ToCharArray() | ForEach-Object {
        if ($invalid -contains $_) { '-' } else { $_ }
    }
    return (-join $chars).Trim()
}

$scriptRoot = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $scriptRoot '..')).Path
$sourceCandidate = if ([IO.Path]::IsPathFullyQualified($SourceDir)) {
    $SourceDir
} else {
    Join-Path $repoRoot $SourceDir
}
$outputPath = if ([IO.Path]::IsPathFullyQualified($OutputDir)) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDir)
} else {
    Join-Path $repoRoot $OutputDir
}
$sourcePath = (Resolve-Path -LiteralPath $sourceCandidate).Path
$infoPath = Join-Path $sourcePath 'info.txt'
$buildScript = Join-Path $scriptRoot 'Build.ps1'
$commontools = Join-Path $scriptRoot 'Common.ps1'
$verifyScript = Join-Path $scriptRoot 'VerifyPackage.ps1'

if (-not (Test-Path -LiteralPath $commontools -PathType Leaf)) {
    throw "Missing required common tools: $commontools"
}
. $commontools

if (-not (Test-Path -LiteralPath $buildScript -PathType Leaf)) {
    throw "Missing required build script: $buildScript"
}
if (-not (Test-Path -LiteralPath $verifyScript -PathType Leaf)) {
    throw "Missing required package verifier: $verifyScript"
}

& $buildScript -SourceDir $sourcePath -LiveReload:$false
if ($LASTEXITCODE -ne 0) {
    throw 'Package build failed.'
}

$modInfo = Get-ModInfo -InfoPath $infoPath
$metadataName = $modInfo.Name
$version = $modInfo.DisplayedVersion

if (-not $PackageName) {
    $PackageName = $metadataName
}
if (-not $version) {
    throw "Missing required [DISPLAYED_VERSION] in $infoPath"
}
if (-not $PackageName) {
    throw "Missing required [NAME] in $infoPath"
}

$safePackageName = ConvertTo-SafeFileName -Name $PackageName
$safeVersion = ConvertTo-SafeFileName -Name $version
if (-not $safePackageName) {
    throw "Package name does not contain any usable filename characters: $PackageName"
}
if (-not $safeVersion) {
    throw "Version does not contain any usable filename characters: $version"
}
$zipPath = Join-Path $outputPath "$safePackageName-$safeVersion.zip"
$expandedPath = Join-Path $outputPath $safePackageName
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) "DFHackModPublish-$([guid]::NewGuid())"
$stagingRoot = $tempRoot

New-Item -ItemType Directory -Force -Path $outputPath | Out-Null
New-Item -ItemType Directory -Force -Path $stagingRoot | Out-Null

try {
    Get-ChildItem -LiteralPath $sourcePath -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $stagingRoot -Recurse -Force
    }

    if (Test-Path -LiteralPath $expandedPath) {
        Remove-Item -LiteralPath $expandedPath -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $expandedPath | Out-Null
    Get-ChildItem -LiteralPath $stagingRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $expandedPath -Recurse -Force
    }

    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory(
        $stagingRoot,
        $zipPath,
        [IO.Compression.CompressionLevel]::Optimal,
        $false)

    $verifyArgs = @{
        SourceDir = $sourcePath
        ZipPath = $zipPath
        ExpandedPath = $expandedPath
    }
    & $verifyScript @verifyArgs
    if ($LASTEXITCODE -ne 0) {
        throw 'Package verification failed.'
    }
    Write-Host "Created $zipPath"
    Write-Host "Created $expandedPath"
    Write-Host "For manual installation, copy '$expandedPath' to the Dwarf Fortress 'mods' folder so the final path is 'mods\$safePackageName\info.txt'."
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
