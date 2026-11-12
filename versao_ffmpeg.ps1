#requires -Version 7.0
function Read-FfmpegVersionHeader {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Output,
        [AllowNull()][object]$Tool,
        [AllowNull()][object]$ExpectedBuildVersion
    )
    if ($Tool -isnot [string] -or ($Tool -cne 'ffmpeg' -and $Tool -cne 'ffprobe')) { throw 'Tool invalido' }
    if ($Output -isnot [string] -or $Output.Length -lt 1 -or $Output.Length -gt 65536) { throw 'Output invalido' }
    if ($ExpectedBuildVersion -isnot [string] -or $ExpectedBuildVersion.Length -gt 160 -or $ExpectedBuildVersion -cnotmatch '\An[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9]+-g[0-9a-f]{7,40})?\z') { throw 'ExpectedBuildVersion invalido' }

    $line = $Output -replace '\r?\n|\r', "`n" -split "`n" | Select-Object -First 1
    if ($null -eq $line -or $line.Length -gt 512) {
        throw 'Invalid header line'
    }

    $prefix = $Tool + ' version '
    if (-not $line.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
        throw 'Invalid version header prefix'
    }

    $rest = $line.Substring($prefix.Length)
    $token = ($rest -split '[ \t]',2)[0]

    if ([string]::IsNullOrEmpty($token)) {
        throw 'Failed to extract version token'
    }

    $validToken = $false
    if ($token -ceq $ExpectedBuildVersion) {
        $validToken = $true
    } elseif ($token -cmatch "\A$([regex]::Escape($ExpectedBuildVersion))-([0-9]{8})\z") {
        $dateStr = $matches[1]
        try {
            $dt = [datetime]::ParseExact($dateStr, 'yyyyMMdd', [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None)
            $validToken = $true
        } catch {
            $validToken = $false
        }
    }

    if (-not $validToken) {
        throw 'Invalid version token'
    }

    return @{
        tool           = $Tool
        build_version  = $ExpectedBuildVersion
        version_token  = $token
    }
}
