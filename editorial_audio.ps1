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
