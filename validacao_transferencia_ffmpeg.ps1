#requires -Version 7.0
. (Join-Path $PSScriptRoot 'uris_release_ffmpeg.ps1')

function Test-FfmpegArchiveTransfer {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Uri,
        [AllowNull()][object]$Destination,
        [AllowNull()][object]$ExpectedSize,
        [AllowNull()][object]$ExpectedSha256
    )

    try {
        # Uri: converter para [uri] se string, exigir DnsSafeHost github.com e AbsolutePath terminar com .zip
        if ($null -eq $Uri) { return $false }
        $uriString = $null
        if ($Uri -is [string]) {
            $uriString = $Uri
        } elseif ($Uri -is [uri]) {
            $uriString = $Uri.ToString()
        } else {
            return $false
        }
        if ([string]::IsNullOrWhiteSpace($uriString)) { return $false }
        $uriObj = $null
        if (-not [uri]::TryCreate($uriString, [UriKind]::Absolute, [ref]$uriObj)) { return $false }
        if (-not $uriObj.IsAbsoluteUri) { return $false }
        if ($uriObj.Scheme -ne 'https') { return $false }
        if ($uriObj.Port -ne 443) { return $false }
        if ($uriObj.DnsSafeHost -cne 'github.com') { return $false }
        if (-not $uriObj.AbsolutePath.EndsWith('.zip', [StringComparison]::Ordinal)) { return $false }

        # Testar helper Test-FfmpegRequestUri
        if (-not (Test-FfmpegRequestUri -Uri $Uri)) { return $false }

        # Destination: exigir [IO.Stream] e CanWrite
        if ($null -eq $Destination) { return $false }
        if ($Destination -isnot [IO.Stream]) { return $false }
        if (-not $Destination.CanWrite) { return $false }

        # ExpectedSize: exigir [long] entre 1 e 536870912
        if ($null -eq $ExpectedSize) { return $false }
        if ($ExpectedSize -isnot [long]) { return $false }
        if ($ExpectedSize -lt 1 -or $ExpectedSize -gt 536870912) { return $false }

        # ExpectedSha256: exigir string ASCII de 64 caracteres hexadecimais minúsculos
        if ($null -eq $ExpectedSha256) { return $false }
        if ($ExpectedSha256 -isnot [string]) { return $false }
        if ($ExpectedSha256.Length -ne 64) { return $false }
        if ( $ExpectedSha256 -cnotmatch '\A[0-9a-f]{64}\z') { return $false }

        return $true
    } catch {
        return $false
    }
}
