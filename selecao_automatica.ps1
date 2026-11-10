#requires -Version 7.0
function Normal([string]$Value) {
    if ($null -eq $Value) { return '' }
    $decomposed = $Value.Normalize([Text.NormalizationForm]::FormD).ToLowerInvariant()
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $decomposed.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -eq [Globalization.UnicodeCategory]::NonSpacingMark) { continue }
        if ([char]::IsLetterOrDigit($c)) { [void]$sb.Append($c) }
        else { [void]$sb.Append(' ') }
    }
    return ([regex]::Replace($sb.ToString(), '\s+', ' ')).Trim()
}

function Is-ExactArtistAudio([string]$Title, [string]$Channel, [string]$Artist, [string]$Song) {
    $a = Normal $Artist; $s = Normal $Song
    $c = Normal $Channel; $t = Normal $Title
    if ($c -notin @($a, ($a + ' topic'))) { return $false }
    return ($t -in @($s, ($s + ' audio'), ($a + ' ' + $s),
            ($a + ' ' + $s + ' audio'), ($a + ' ' + $s + ' official audio')))
}

function Select-AutoCandidate($Items, [string]$Artist, [string]$Song) {
    $exact = @($Items | Where-Object { Is-ExactArtistAudio ([string]$_.titulo) ([string]$_.canal) $Artist $Song })
    if ($exact.Count -ne 1) { return $null }
    return $exact[0]
}
