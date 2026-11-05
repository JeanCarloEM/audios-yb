# Executar: powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/qualidade.tests.ps1
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1.0
$script:Root=Split-Path $PSScriptRoot -Parent
. (Join-Path $script:Root 'ferramentas_portateis.ps1')
$testToolsRoot=if([string]::IsNullOrWhiteSpace($env:AUDIOS_YB_TEST_TOOLS_ROOT)){$script:Root}else{[IO.Path]::GetFullPath($env:AUDIOS_YB_TEST_TOOLS_ROOT)}
$testTools=Resolve-ScriptTools -Root $testToolsRoot
$script:Ffmpeg=$testTools.Ffmpeg
$script:Ffprobe=$testTools.Ffprobe
$script:Exe=$testTools.Exe
$script:Policy='fidelidade-128-v1'
$script:Evidencias=@{}
$script:Out=$PSScriptRoot
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root 'baixar_audios_ytdlp.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Erro de sintaxe'}
foreach($def in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) {
    . ([scriptblock]::Create($def.Extent.Text))
}
$work=Join-Path $PSScriptRoot ('.runtime-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
$script:Passed=0
function Assert($Condition,[string]$Message){if(-not $Condition){throw $Message};$script:Passed++}
function Media([string]$Name,[string[]]$Encoding){
    $path=Join-Path $work $Name
    $run=Invoke-Ytdlp -Executable $script:Ffmpeg -Arguments (@('-nostdin','-v','error','-f','lavfi','-i','anoisesrc=sample_rate=44100:duration=4:seed=1','-ac','2')+$Encoding+@('-n',$path))
    if($run.code){throw $run.err};return $path
}
function Evidence([string]$File,[string]$Format,[string]$Quality,[double]$Minimum){
    $hash=(Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant()
    $script:Evidencias['TestVideo01|'+$Format+'|'+$hash]=@{qualidade=$Quality;bitrate_minimo_historico_kbps=$Minimum;
        origem='Fixture local sintetica gerada diretamente por FFmpeg';historico='Ruido PCM gerado localmente, codificado uma unica vez nesta fixture'}
}
$low=Media 'low.mp3' @('-c:a','libmp3lame','-b:a','96k')
$high=Media 'high.mp3' @('-c:a','libmp3lame','-b:a','192k')
$exact=Media 'exact.mp3' @('-c:a','libmp3lame','-b:a','128k')
$flac=Media 'lossless.flac' @('-c:a','flac')
$webm=Media 'source.webm' @('-c:a','libopus','-b:a','160k','-vbr','off')
$vbr=Media 'vbr.webm' @('-c:a','libopus','-b:a','160k')
$aac=Media 'source.aac' @('-c:a','aac','-b:a','160k')
$p=Probe-Audio $exact
Assert (Test-FinalAudio $exact $p) 'MP3 CBR 128 deve ser admissivel tecnicamente'
Assert (-not (Test-SourceEvidence 'TestVideo01' '128' ((Get-FileHash $exact).Hash.ToLowerInvariant()) $p).ok) 'Bitrate isolado nao comprova procedencia'
$truncated=Complete-Audio $exact (Join-Path $work 'truncated-final') 'TestVideo01' @{id='128';operacao='nativo';duracao_origem=240}
Assert (-not $truncated.ok) 'Fonte decodificavel mas truncada perante metadados deve ser rejeitada'
Assert ((Probe-Audio $vbr).bitrate_medido_kbps -lt 128) 'VBR nominal160 desta fixture fica abaixo do minimo efetivo'
Evidence $low '96' 'perdas_verificadas' 96
$r=Complete-Audio $low (Join-Path $work 'low-final') 'TestVideo01' @{id='96';operacao='nativo'}
Assert (-not $r.ok) 'Fonte inferior deve ser rejeitada'
$inflated=Join-Path $work 'inflated.mp3'
$run=Invoke-Ytdlp -Executable $script:Ffmpeg -Arguments @('-v','error','-i',$low,'-c:a','libmp3lame','-b:a','192k',$inflated)
if($run.code){throw $run.err}
Evidence $inflated 'inflated' 'perdas_verificadas' 96
$r=Complete-Audio $inflated (Join-Path $work 'inflated-final') 'TestVideo01' @{id='inflated';operacao='nativo'}
Assert (-not $r.ok) 'Inflar 96 para 192 nao pode obter conformidade'
Evidence $high '192' 'perdas_verificadas' 192
$hash=(Get-FileHash $high).Hash
$r=Complete-Audio $high (Join-Path $work 'native-final') 'TestVideo01' @{id='192';operacao='nativo'}
Assert $r.ok 'Nativo 192 documentado deve ser preservado'
Assert ((Get-FileHash (Join-Path $work $r.arquivo)).Hash -eq $hash) 'Nativo nao pode ser recodificado'
Evidence $flac 'flac' 'sem_perdas_verificada' 0
$r=Complete-Audio $flac (Join-Path $work 'flac-final') 'TestVideo01' @{id='flac';operacao='transcodificacao'}
Assert $r.ok 'Lossless documentado deve permitir conversao excepcional'
Assert ($r.probe.bitrate_medido_kbps -ge 128) 'Resultado AAC medido deve ser >=128'
Assert ([IO.File]::Exists($flac)) 'Fonte convertida deve ser preservada'
Evidence $webm 'opus' 'perdas_verificadas' 160
$r=Complete-Audio $webm (Join-Path $work 'opus-final') 'TestVideo01' @{id='opus';operacao='transcodificacao'}
if(-not $r.ok){Write-Host ($r | ConvertTo-Json -Depth 10)}; Assert $r.ok 'Opus adequado e documentado deve gerar M4A genuino'
Evidence $aac 'aac' 'perdas_verificadas' 160
$r=Complete-Audio $aac (Join-Path $work 'remux-final') 'TestVideo01' @{id='aac';operacao='remux'}
Assert ($r.ok -and $r.auditoria.conversao -eq 'remux_sem_recodificacao') 'AAC compativel deve usar remux'
$fake=Join-Path $work 'fake.m4a'; Copy-Item -LiteralPath $webm -Destination $fake
Assert (-not (Test-FinalAudio $fake (Probe-Audio $fake))) 'Extensao falsa deve ser rejeitada'
$formats=@(Get-Formats ([pscustomobject]@{formats=@(
    @{format_id='low';ext='m4a';vcodec='none';acodec='mp4a.40.2';abr=92},
    @{format_id='192';ext='m4a';vcodec='none';acodec='mp4a.40.2';abr=192},
    @{format_id='128';ext='mp3';vcodec='none';acodec='mp3';abr=128},
    @{format_id='opus';ext='webm';vcodec='none';acodec='opus';abr=128})}))
Assert ($formats.Count -eq 3 -and $formats[0].id -eq '128' -and $formats[1].id -eq '192') 'Nativos >=128, alvo128 e nativos antes de conversao'
$broken=Join-Path $work 'broken.m4a'; [IO.File]::WriteAllText($broken,'invalid')
$rejected=$false;try{Probe-Audio $broken | Out-Null}catch{$rejected=$true}
Assert $rejected 'Arquivo corrompido deve ser rejeitado'
$script:Out=Join-Path $work 'destino';$script:Control=Join-Path $script:Out '.controle'
$script:StateFile=Join-Path $script:Control 'estado.json';$script:Utf8=New-Object Text.UTF8Encoding($false)
New-Item -ItemType Directory -Path $script:Control -Force | Out-Null
$legacy=Join-Path $script:Out 'legado.webm';Copy-Item -LiteralPath $webm -Destination $legacy
$legacyHash=(Get-FileHash $legacy).Hash.ToLowerInvariant()
$script:State=@{videos=@{TestVideo01=@{arquivo='legado.webm';sha256=$legacyHash;artista='Teste';musica='Fixture'}};
    registros=@{one=@{video_id='TestVideo01';resultado='baixado';arquivo='legado.webm'}};buscas=@{}}
Audit-Legacy
Assert (-not (Test-Path -LiteralPath $legacy)) 'WebM legado nao deve ficar entre resultados finais'
$archive=Join-Path $script:Control $script:State.videos.TestVideo01.arquivo_legado
Assert ((Get-FileHash -LiteralPath $archive).Hash.ToLowerInvariant() -eq $legacyHash) 'Migracao deve preservar bytes do legado'
Assert ($script:State.registros.one.resultado -eq 'pendente_qualidade') 'Sucesso antigo deve virar pendencia de qualidade'
Audit-Legacy
Assert ((Get-ChildItem (Join-Path $script:Control 'legado') -File).Count -eq 1) 'Migracao deve ser idempotente'
$json=ConvertFrom-Json -InputObject '{"lista":[{"id":"a"},{"id":"b"}]}'
$table=To-Hashtable $json
Assert ($table.lista.Count -eq 2 -and $table.lista[0].id -eq 'a') 'Arrays JSON devem sobreviver a conversao do estado'
Evidence $flac 'flac-low-history' 'sem_perdas_verificada' 96
$r=Complete-Audio $flac (Join-Path $work 'false-lossless-final') 'TestVideo01' @{id='flac-low-history';operacao='transcodificacao'}
Assert (-not $r.ok) 'Lossless derivado de fonte comprimida inferior deve ser rejeitado'
$orphan=Join-Path $script:Out 'sem-estado.webm';Copy-Item -LiteralPath $webm -Destination $orphan
Audit-Legacy
Assert (-not (Test-Path -LiteralPath $orphan) -and $script:State.arquivos_preservados.Count -eq 1) 'Audio sem estado deve ser preservado fora dos resultados finais'
$silent=Join-Path $work 'silencio.m4a'
$run=Invoke-Ytdlp -Executable $script:Ffmpeg -Arguments @('-nostdin','-v','error','-f','lavfi','-i','anullsrc=r=44100:cl=stereo','-t','4','-c:a','alac',$silent)
if($run.code){throw $run.err}
Assert (-not (Test-FinalAudio $silent (Probe-Audio $silent))) 'Resultado final abaixo de128 deve ficar pendente mesmo sem perdas; nunca preencher artificialmente'
Write-Host ('PASS: '+$script:Passed+' verificacoes; fixtures: '+$work)
