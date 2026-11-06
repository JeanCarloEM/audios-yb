#!/usr/bin/env pwsh
# Cria fixture MP3 sintética com 7 tags e verifica via ffprobe
# Unidade: somente geração e verificação; sem remux/marcador/payload

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'processo_capturado.ps1')

$fixtureDir = Join-Path $PSScriptRoot ('.runtime-marcador-mp3-fixture-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureDir -ErrorAction Stop | Out-Null
$fixturePath = Join-Path $fixtureDir 'fonte.mp3'

# Gerar MP3 sintético com 7 tags ID3v2 via ffmpeg
$ffmpegArgs = @(
    '-v', 'error',
    '-f', 'lavfi',
    '-i', 'anoisesrc=d=2:r=44100:seed=7',
    '-ac', '2',
    '-c:a', 'libmp3lame',
    '-b:a', '192k',
    '-id3v2_version', '3',
    '-metadata', 'artist=AC/DC',
    '-metadata', 'title=iTunes DJ',
    '-metadata', 'album=Album teste',
    '-metadata', 'track=12',
    '-metadata', 'composer=Autor teste',
    '-metadata', 'genre=Genero teste',
    '-metadata', 'comment=Comentario teste',
    '-n', $fixturePath
)

Invoke-CapturedTestProcess -Program (Join-Path $root 'ffmpeg.exe') -Arguments $ffmpegArgs | Out-Null

# Probe via ffprobe e validar estrutura
$probeArgs = @('-v', 'error', '-of', 'json', '-show_format', '-show_streams', $fixturePath)
$probeResult = Invoke-CapturedTestProcess -Program (Join-Path $root 'ffprobe.exe') -Arguments $probeArgs
$probeJson = $probeResult.Stdout | ConvertFrom-Json

# Assert stream único áudio com codec mp3 e parâmetros esperados
$audioStream = $probeJson.streams | Where-Object { $_.codec_type -eq 'audio' }
if (@($probeJson.streams).Count -ne 1 -or @($audioStream).Count -ne 1) { throw "Esperado 1 stream de áudio, encontrado $($audioStream.Count)" }
if ($audioStream.codec_name -ne 'mp3') { throw "Codec esperado mp3, encontrado $($audioStream.codec_name)" }
if ($audioStream.bit_rate -ne 192000) { throw "bit_rate esperado 192000, encontrado $($audioStream.bit_rate)" }
if ($audioStream.sample_rate -ne 44100) { throw "sample_rate esperado 44100, encontrado $($audioStream.sample_rate)" }
if ($audioStream.channels -ne 2) { throw "channels esperado 2, encontrado $($audioStream.channels)" }
$duration = [double]::Parse([string]$audioStream.duration, [Globalization.CultureInfo]::InvariantCulture); if (-not [double]::IsFinite($duration) -or $duration -le 0) { throw "duration ausente, invalida ou zero" }

# Assert tags ID3v2
$tags = $probeJson.format.tags
if ($tags.artist -cne 'AC/DC') { throw "tag artist incorreta: $($tags.artist)" }
if ($tags.title -cne 'iTunes DJ') { throw "tag title incorreta: $($tags.title)" }
if ($tags.album -cne 'Album teste') { throw "tag album incorreta: $($tags.album)" }
if ($tags.track -cne '12') { throw "tag track incorreta: $($tags.track)" }
if ($tags.composer -cne 'Autor teste') { throw "tag composer incorreta: $($tags.composer)" }
if ($tags.genre -cne 'Genero teste') { throw "tag genre incorreta: $($tags.genre)" }
if ($tags.comment -cne 'Comentario teste') { throw "tag comment incorreta: $($tags.comment)" }

# Assert arquivo não vazio e calcular SHA256
$fileInfo = Get-Item $fixturePath
if ($fileInfo.Length -eq 0) { throw "Fixture MP3 vazio" }
$sha256 = (Get-FileHash -Path $fixturePath -Algorithm SHA256).Hash

# Gerar receipt.json
$receipt = [PSCustomObject]@{
    '$schema' = 'audios-yb-mp3-fixture/v1'
    fixture   = [PSCustomObject]@{
        root = $fixtureDir; sourcepath = $fixturePath
        hash       = $sha256
        size       = $fileInfo.Length
    }
    probe     = $probeJson
    expected_tags = [PSCustomObject]@{
        artist    = 'AC/DC'
        title     = 'iTunes DJ'
        album     = 'Album teste'
        track     = '12'
        composer  = 'Autor teste'
        genre     = 'Genero teste'
        comment   = 'Comentario teste'
    }
    os        = [PSCustomObject]@{
        psversion = $PSVersionTable.PSVersion.ToString()
        os        = [System.Environment]::OSVersion.VersionString
    }
    limitacao = 'Fixture sintetica Windows; remux, marcador e payload ainda nao validados'
}

$receiptPath = Join-Path $fixtureDir 'receipt.json'
$receipt | ConvertTo-Json -Depth 100 | Set-Content -Path $receiptPath -Encoding UTF8 -NoNewline

[pscustomobject]@{receipt_path=$receiptPath}|ConvertTo-Json -Compress
