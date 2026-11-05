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
