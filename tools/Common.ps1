Set-StrictMode -Version Latest

function Import-EnvironmentFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [switch]$AllowMissing
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        if ($AllowMissing) {
            return
        }
        throw "Could not find environment file: $Path"
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $entry = $line.Trim()
        if (-not $entry -or $entry.StartsWith('#')) {
            continue
        }

        if ($entry.StartsWith('export ')) {
            $entry = $entry.Substring(7).TrimStart()
        }

        $separator = $entry.IndexOf('=')
        if ($separator -lt 1) {
            throw "Invalid environment entry in ${Path}: $line"
        }

        $name = $entry.Substring(0, $separator).Trim()
        if ($name -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
            throw "Invalid environment variable name in ${Path}: $name"
        }

        $value = $entry.Substring($separator + 1).Trim()
        if ($value.Length -ge 2) {
            $first = $value[0]
            $last = $value[$value.Length - 1]
            if (($first -eq '"' -and $last -eq '"') -or
                ($first -eq "'" -and $last -eq "'")) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }

        if ($null -eq [Environment]::GetEnvironmentVariable($name, 'Process')) {
            [Environment]::SetEnvironmentVariable($name, $value, 'Process')
        }
    }
}

function Get-ModInfoValue {
    param(
        [Parameter(Mandatory=$true)]
        [string]$InfoText,

        [Parameter(Mandatory=$true)]
        [string]$Key
    )

    $pattern = "\[$([regex]::Escape($Key)):(.*?)\]"
    $match = [regex]::Match($InfoText, $pattern)
    if (-not $match.Success) {
        return $null
    }
    return $match.Groups[1].Value.Trim()
}

function Get-ModInfo {
    param(
        [Parameter(Mandatory=$true)]
        [string]$InfoPath
    )

    if (-not (Test-Path -LiteralPath $InfoPath -PathType Leaf)) {
        throw "Could not find required mod metadata file: $InfoPath"
    }

    $infoText = Get-Content -LiteralPath $InfoPath -Raw
    return [pscustomobject]@{
        Id = Get-ModInfoValue -InfoText $infoText -Key 'ID'
        Name = Get-ModInfoValue -InfoText $infoText -Key 'NAME'
        DisplayedVersion = Get-ModInfoValue -InfoText $infoText -Key 'DISPLAYED_VERSION'
    }
}

function Resolve-DFHackRunner {
    param(
        [string]$RunnerPath,
        [string]$DwarfFortressRoot
    )

    if ($RunnerPath) {
        if (-not (Test-Path -LiteralPath $RunnerPath -PathType Leaf)) {
            throw "Could not find the configured DFHack command runner: $RunnerPath"
        }
        return (Resolve-Path -LiteralPath $RunnerPath).Path
    }

    if ($DwarfFortressRoot) {
        $candidate = Join-Path $DwarfFortressRoot 'hack\dfhack-run.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
        throw "Could not find DFHack's command runner under: $DwarfFortressRoot"
    }

    $command = Get-Command 'dfhack-run.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    throw 'Could not find dfhack-run.exe. Set MOD_COMMAND_RUNNER, pass -DFHackRunner, or pass -DwarfFortressRoot.'
}
