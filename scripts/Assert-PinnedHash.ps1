#Requires -Version 5.1
<#
.SYNOPSIS
    Pin or TOFU-compare a file's SHA256 against a local checksum store.
.DESCRIPTION
    Lookup order: existing pin in -PinStore (default %LOCALAPPDATA%\dotfiles-windows\checksums.json).
    Missing key → Trust On First Use (record the hash). Mismatch → throw (caller must abort).
#>
function Assert-PinnedHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string]$PinStore
    )

    if (-not $PinStore) {
        $localDir = Join-Path $env:LOCALAPPDATA "dotfiles-windows"
        if (-not (Test-Path $localDir)) {
            New-Item -ItemType Directory -Path $localDir -Force | Out-Null
        }
        $PinStore = Join-Path $localDir "checksums.json"
    }

    if (-not (Test-Path -LiteralPath $FilePath)) {
        throw "SHA256 pin failed: file not found ($FilePath)"
    }

    $actual = (Get-FileHash -LiteralPath $FilePath -Algorithm SHA256).Hash.ToUpperInvariant()
    $map = @{}
    if (Test-Path -LiteralPath $PinStore) {
        $raw = [System.IO.File]::ReadAllText($PinStore, [System.Text.Encoding]::UTF8)
        if ($raw -and $raw.Trim()) {
            $obj = $raw | ConvertFrom-Json
            foreach ($p in $obj.PSObject.Properties) {
                if ($null -ne $p.Value) {
                    $map[$p.Name] = $p.Value.ToString()
                }
            }
        }
    }

    if ($map.ContainsKey($Name)) {
        $expected = $map[$Name].ToUpperInvariant()
        if ($expected -ne $actual) {
            throw "SHA256 mismatch for '${Name}': expected $expected actual $actual. Aborting."
        }
        Write-Host "   [SHA256 pin match] $Name" -ForegroundColor DarkGray
        return $actual
    }

    $map[$Name] = $actual
    $json = $map | ConvertTo-Json -Compress
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($PinStore, $json, $utf8NoBom)
    Write-Host "   [SHA256 TOFU] first-seen $Name pinned as $actual" -ForegroundColor DarkGray
    return $actual
}
