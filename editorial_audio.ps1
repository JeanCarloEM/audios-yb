#requires -Version 7.0
# RCF 7.3: normalizacao pura; ainda sem integracao ao principal/tags.
function ConvertTo-CollectionMarker {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [AllowNull()][AllowEmptyString()][string]$Value = ''
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $normalized = $Value.Trim().Normalize([Text.NormalizationForm]::FormC)
    $letters = @(
        [Globalization.UnicodeCategory]::UppercaseLetter,
        [Globalization.UnicodeCategory]::LowercaseLetter,
        [Globalization.UnicodeCategory]::TitlecaseLetter,
        [Globalization.UnicodeCategory]::ModifierLetter,
        [Globalization.UnicodeCategory]::OtherLetter
    )
    $result = [Text.StringBuilder]::new()
    $firstLetter = $true
    for ($offset = 0; $offset -lt $normalized.Length;) {
        $width = 1
        if ([char]::IsHighSurrogate($normalized[$offset]) -and
            $offset + 1 -lt $normalized.Length -and
            [char]::IsLowSurrogate($normalized[$offset + 1])) { $width = 2 }
        $part = $normalized.Substring($offset, $width)
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($normalized, $offset)
        if ($category -in $letters) {
            if ($firstLetter) { $part = $part.ToUpperInvariant(); $firstLetter = $false }
            else { $part = $part.ToLowerInvariant() }
        }
        [void]$result.Append($part)
        $offset += $width
    }
    return $result.ToString().Normalize([Text.NormalizationForm]::FormC)
}

# RCF 7.3: decisao deterministica sem I/O, subprocessos ou midia.
function Get-CollectionMarkerDecision {
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$CurrentValue = '',
        [AllowNull()][AllowEmptyString()][string]$RequestedValue = ''
    )
    $normalizedRequested = ConvertTo-CollectionMarker -Value $RequestedValue
    if ([string]::IsNullOrEmpty($normalizedRequested)) {
        return [PSCustomObject]@{ Action = 'keep'; Value = $CurrentValue; Reason = 'absent' }
    }
    if ([string]::IsNullOrEmpty($CurrentValue)) {
        return [PSCustomObject]@{ Action = 'apply'; Value = $normalizedRequested; Reason = 'empty_field' }
    }
    if ([string]::Equals($normalizedRequested, $CurrentValue, [StringComparison]::Ordinal)) {
        return [PSCustomObject]@{ Action = 'keep'; Value = $CurrentValue; Reason = 'already_present' }
    }
    return [PSCustomObject]@{ Action = 'unsupported'; Value = $CurrentValue; Reason = 'multiple_values_not_validated' }
}

# RCF 7.3: hash comprimido de áudio via ffmpeg hash mode
function Get-CompressedAudioHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$File,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Ffmpeg
    )

    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        throw [System.IO.FileNotFoundException]::new("Arquivo não encontrado: $File", $File)
    }

    $result = Invoke-Ytdlp -Executable $Ffmpeg -Arguments @('-v', 'error', '-i', $File, '-map', '0:a:0', '-c:a', 'copy', '-f', 'hash', '-hash', 'sha256', '-') -TimeoutSeconds 30

    if ($result.timeout -eq $true) {
        throw [System.TimeoutException]::new("Timeout ao processar: $File")
    }

    if ($result.code -ne 0) {
        throw [System.InvalidOperationException]::new("Comando falhou: $($result.err)")
    }

    $match = [regex]::Match($result.out, '(?im)^SHA256=([0-9a-f]{64})\s*$')
    if (-not $match.Success) {
        throw [System.InvalidOperationException]::new("Hash não encontrado na saída: $($result.out)")
    }

    return $match.Groups[1].Value.ToUpperInvariant()
}


function Get-AudioMetadataSnapshot {
 [CmdletBinding()]
 param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$File,
       [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Ffprobe)
 if(-not (Test-Path -LiteralPath $File -PathType Leaf)){throw [IO.FileNotFoundException]::new('Arquivo ausente',$File)}
 $run=Invoke-Ytdlp -Executable $Ffprobe -Arguments @('-v','error','-protocol_whitelist','file','-show_streams','-show_format','-of','json','-i',$File) -TimeoutSeconds 30
 if($run.timeout){throw [TimeoutException]::new('Timeout ao ler metadados')}
 if($run.code -ne 0){throw [InvalidOperationException]::new('ffprobe: '+$run.err)}
 $info=ConvertFrom-Json -InputObject $run.out -ErrorAction Stop
 if($null -eq $info.format -or @($info.streams).Count -ne 1 -or $info.streams[0].codec_type -cne 'audio'){throw [IO.InvalidDataException]::new('Exigir formato e exatamente um stream de audio')}
 return $info
}
