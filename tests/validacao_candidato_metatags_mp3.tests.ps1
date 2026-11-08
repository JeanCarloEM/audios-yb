#requires -Version 7
# Prova sintetica Windows; nao certifica procedencia/historico nem timeout real.
# tests/validacao_candidato_metatags_mp3.tests.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$script:Ffmpeg=Join-Path $root 'ffmpeg.exe';$script:Ffprobe=Join-Path $root 'ffprobe.exe'
. (Join-Path $root 'tests' 'processo_capturado.ps1')
. (Join-Path $root 'argumentos_metatags_mp3.ps1')
. (Join-Path $root 'candidato_metatags_mp3.ps1')
. (Join-Path $root 'editorial_audio.ps1')
. (Join-Path $root 'mapa_tags_editoriais.ps1')
. (Join-Path $root 'comparacao_tags_ordinal.ps1')
. (Join-Path $root 'validacao_tags_editoriais.ps1')
. (Join-Path $root 'validacao_candidato_metatags_mp3.ps1')

$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'baixar_audios_ytdlp.ps1'),[ref]$t,[ref]$e)
if($e.Count){throw 'Main parse'}
foreach($name in @('Probe-Audio','Test-FinalAudio')){
 $nodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
 if($nodes.Count -ne 1){throw 'AST function'}
 . ([scriptblock]::Create($nodes[0].Extent.Text))
}
# Adapter Invoke-Ytdlp
function Invoke-Ytdlp {
 param([string]$Executable,[string[]]$Arguments,[int]$TimeoutSeconds=30)
 $run=Invoke-CapturedTestProcess -Program $Executable -Arguments $Arguments -TimeoutMs ([int]([Math]::Min($TimeoutSeconds,30)*1000))
 return @{code=$run.ExitCode;out=$run.Stdout;err=$run.Stderr;timeout=$false}
}

# Fixture positiva192k; negativos pendentes
$runtimeDir = Join-Path $root 'tests' ('.runtime-editorial-native-' + [System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $runtimeDir | Out-Null

$srcPath = Join-Path $runtimeDir 'src_sample_44100_ac2_b192k.mp3'
$srcArgs = @('-nostdin','-v','error','-f','lavfi','-i','anoisesrc=sample_rate=44100:duration=2:seed=4321','-ac','2','-c:a','libmp3lame','-b:a','192k','-threads','1','-id3v2_version','3','-metadata','keep_tag=Sentinela ç','-metadata','marcador_coletanea=Grupo','-n',$srcPath)
$ytdlpResult = Invoke-Ytdlp -Executable (Join-Path $root 'ffmpeg.exe') -Arguments $srcArgs -TimeoutSeconds 30
if ($ytdlpResult.code -ne 0) { throw "Falha ao gerar fonte 192k: $($ytdlpResult.err)" }

# Obter SHA256 da fonte 192k
$srcSha = (Get-FileHash -Path $srcPath -Algorithm SHA256).Hash

$payloadSha = Get-CompressedAudioHash -File $srcPath -Ffmpeg (Join-Path $root 'ffmpeg.exe')
# Teste positivo: candidato válido
$outputPath = Join-Path $runtimeDir 'candidato_positivo.mp3'
$updates = @{ artist = 'Artistaé'; title = 'FaixaiTunes'; album = 'Coletânea'; track = '003'; composer = 'AC/DC' }
$candidato = New-Mp3EditorialTagCandidate -File $srcPath -Output $outputPath -Updates $updates -Ffmpeg (Join-Path $root 'ffmpeg.exe')
if ($candidato.Validated -isnot [bool] -or $candidato.Validated) { throw 'Writer deve retornar Validated=false' }

$srcProbe = Probe-Audio -File $srcPath
$candProbe = Probe-Audio -File $outputPath

$srcSha2 = (Get-FileHash -Path $srcPath -Algorithm SHA256).Hash
$candSha = (Get-FileHash -Path $outputPath -Algorithm SHA256).Hash



$verificado = Assert-Mp3EditorialTagCandidate -File $srcPath -Candidate $outputPath -Updates $updates
if (-not $verificado.Verified) { throw 'Assert-Mp3EditorialTagCandidate rejeitou candidato positivo' }

if ($srcSha -ne $srcSha2) { throw 'Fonte 192k alterada após geração' }
if ($srcSha -ne $verificado.SourceSha256) { throw 'SHA fonte não confere' }
if ($candSha -ne $verificado.CandidateSha256) { throw 'SHA candidato não confere' }
if ((Get-Item $outputPath).Length -ne $verificado.CandidateSizeBytes) { throw 'Tamanho candidato não confere' }
if ($payloadSha -ne $verificado.PayloadSha256) { throw 'SHA payload não confere' }
foreach($measured in @($srcProbe,$candProbe)){
 if($measured.codec -cne 'mp3' -or $measured.container -cne 'mp3' -or $measured.amostragem -ne 44100 -or $measured.canais -ne 2 -or $measured.bitrate_medido_kbps -lt 128 -or $measured.duracao -lt 2 -or $measured.duracao -gt 3){throw 'Metricas nativas invalidas'}
}

# Resultado JSON
$resultado = @{ sourcePath = $srcPath; candidatePath = $outputPath; sourceSha256 = $srcSha; candidateSha256 = $candSha; candidateSizeBytes = (Get-Item $outputPath).Length; payloadSha256 = $payloadSha; sourceProbe = $srcProbe; candidateProbe = $candProbe }
$resultado | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $runtimeDir 'resultado.json')

Write-Host 'EDITORIAL_NATIVE_POSITIVE_PASS' -ForegroundColor Green