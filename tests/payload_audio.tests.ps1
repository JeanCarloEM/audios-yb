#requires -Version 7.0

param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$FixtureRoot)
$ErrorActionPreference = 'Stop'

$script:PayloadTestRoot = $PSScriptRoot
. (Join-Path $script:PayloadTestRoot '../editorial_audio.ps1')

function Test-AudioPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FixtureRoot
    )

    $script:FixturePath = Join-Path $FixtureRoot 'fonte.mp3'
    $script:MarkerPath = Join-Path $FixtureRoot 'marcado.mp3'
    $script:FfmpegPath = Join-Path $script:PayloadTestRoot '../ffmpeg.exe'
    $script:ProofPath = Join-Path $FixtureRoot 'marker-proof.json'

    $script:ExpectedHash = '0A11D18D8D81BF4A31A13C72CD7BBAA81B4C4D11A35B8DBAF0EA8EEA126C940F'

    

    

    # Testes
    $script:Proof = Get-Content $script:ProofPath -Raw | ConvertFrom-Json
    if ($script:Proof.schema -cne 'audios-yb-mp3-marker-proof/v1') {throw 'Schema divergente'}

    if ((Get-FileHash -LiteralPath $script:FixturePath).Hash -ne $script:Proof.source_file_hash) {
        throw "Fixture fonte.mp3 diverge do hash esperado."
    }

    $actualFixtureHash = Get-CompressedAudioHash -File $script:FixturePath -Ffmpeg $script:FfmpegPath
    if ($actualFixtureHash -ne $script:ExpectedHash) {
        throw "Hash de fonte.mp3 inesperado: $actualFixtureHash"
    }

    $actualMarkerHash = Get-CompressedAudioHash -File $script:MarkerPath -Ffmpeg $script:FfmpegPath
    if ($actualMarkerHash -ne $script:ExpectedHash) {
        throw "Hash de marcado.mp3 inesperado: $actualMarkerHash"
    }

    foreach($value in @($actualFixtureHash,$actualMarkerHash)){
        if($value -isnot [string] -or $value -cnotmatch '^[0-9A-F]{64}$'){throw 'Hash sem contrato string64hex'}
    }
    $literalPath=Join-Path $FixtureRoot ('payload ['+[Guid]::NewGuid().ToString('N')+'].mp3')
    [IO.File]::Copy($script:FixturePath,$literalPath,$false)
    if((Get-CompressedAudioHash -File $literalPath -Ffmpeg $script:FfmpegPath) -cne $script:ExpectedHash){throw 'Path literal com colchetes falhou'}
    # Negativo 1: arquivo inexistente
    try {
        Get-CompressedAudioHash -File 'inexistente.mp3' -Ffmpeg $script:FfmpegPath
        throw "Deveria ter lançado exceção para arquivo inexistente."
    } catch {
        if ($_.Exception -isnot [System.IO.FileNotFoundException]) {
            throw "Exceção inesperada para arquivo inexistente: $($_.Exception.GetType().FullName)"
        }
    }

    # Negativo 2: ffprobe.exe não compatível
    $script:IncompatibleFfmpeg = Join-Path $script:PayloadTestRoot '../ffprobe.exe'
    try {
        Get-CompressedAudioHash -File $script:FixturePath -Ffmpeg $script:IncompatibleFfmpeg
        throw "Deveria ter lançado exceção para comando incompatível."
    } catch {
        if ($_.Exception -isnot [System.InvalidOperationException]) {
            throw "Exceção inesperada para comando incompatível: $($_.Exception.GetType().FullName)"
        }
    }

    Write-Host "PASS: payload_audio.tests.ps1" -ForegroundColor Green
    Write-Host "Payload: $script:ExpectedHash" -ForegroundColor Cyan
}

Test-AudioPayload -FixtureRoot $FixtureRoot
