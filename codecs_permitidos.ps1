function Test-AllowedAudioCodec {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Codec
    )

    if ($Codec -isnot [string]) {
        return $false
    }

    return ([string]::Equals($Codec, 'aac', [StringComparison]::OrdinalIgnoreCase) -or [string]::Equals($Codec, 'ac3', [StringComparison]::OrdinalIgnoreCase))
}
