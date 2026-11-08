#requires -Version 5.1
Set-StrictMode -Version Latest

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Join-Path $here '..\codecs_permitidos.ps1' -Resolve)

. $sut

$testCases = @(
    @{ Codec = 'aac'; Expected = $true }
    @{ Codec = 'AAC'; Expected = $true }
    @{ Codec = 'ac3'; Expected = $true }
    @{ Codec = 'AC3'; Expected = $true }
    @{ Codec = $null; Expected = $false }
    @{ Codec = ''; Expected = $false }
    @{ Codec = ' '; Expected = $false }
    @{ Codec = ' aac'; Expected = $false }
    @{ Codec = 'aac '; Expected = $false }
    @{ Codec = 'eac3'; Expected = $false }
    @{ Codec = 'mp3'; Expected = $false }
    @{ Codec = 'opus'; Expected = $false }
    @{ Codec = 'alac'; Expected = $false }
    @{ Codec = 'flac'; Expected = $false }
    @{ Codec = 'pcm_s16le'; Expected = $false }
    @{ Codec = 'aac_extra'; Expected = $false }
    @{ Codec = 'ac3x'; Expected = $false }
    @{ Codec = 'mp4a'; Expected = $false }
    @{ Codec = 'mp4a.40.2'; Expected = $false }
    @{ Codec = 'm4a'; Expected = $false }
    @{ Codec = 'mp4'; Expected = $false }
    @{ Codec = @('aac'); Expected = $false }
    @{ Codec = 123; Expected = $false }
    @{ Codec = @{ Key = 'aac' }; Expected = $false }
    @{ Codec = @('aac','ac3'); Expected = $false }
    @{ Codec = [pscustomobject]@{ Codec = 'aac' }; Expected = $false }
)

$passed = 0
$failed = 0

foreach ($tc in $testCases) {
    $result = Test-AllowedAudioCodec -Codec $tc.Codec
    if (($result -is [bool]) -and ($result -ceq $tc.Expected)) {
        $passed++
    } else {
        $failed++
        Write-Host "FAIL: Codec='$($tc.Codec)' expected $($tc.Expected) got $result" -ForegroundColor Red
    }
}

if ($failed -gt 0) { throw ('CODEC_ALLOWLIST_FAIL: '+$failed) }
if ($passed -ne 26 -or $testCases.Count -ne 26) { throw 'Quantidade de casos divergente' }
Write-Host ('CODEC_ALLOWLIST_PASS cases='+$passed)
exit 0
