#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1.0
$repo=Split-Path -Parent $PSScriptRoot
$script:Root=$repo;$script:Exe=Join-Path $repo 'yt-dlp.exe'
$script:Ffmpeg=Join-Path $repo 'ffmpeg.exe';$script:Ffprobe=Join-Path $repo 'ffprobe.exe'
$script:Policy='fidelidade-128-v1';$script:Utf8=[Text.UTF8Encoding]::new($false);$script:Lock=$null
. (Join-Path $repo 'execucao_unica.ps1')
. (Join-Path $repo 'publicacao_pendente.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'baixar_audios_ytdlp.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Sintaxe de producao invalida'}
foreach($name in @('Invoke-Ytdlp','Probe-Audio','Test-FinalAudio','Test-SourceEvidence','Save-State','New-Record')){
 $defs=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
 if($defs.Count -ne 1){throw 'Funcao ambigua'}
 . ([scriptblock]::Create($defs[0].Extent.Text))
}
# Fonte/provas sinteticas locais. Nao homologa identidade ou procedencia de videos reais.
$generated=@(& (Join-Path $repo 'tests/criar_fixture_marcador_mp3.ps1'))|Out-String
$receipt=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText((ConvertFrom-PublicationJson -Json $generated).receipt_path))
$source=$receipt.fixture.sourcepath;$sourceHash=$receipt.fixture.hash.ToLowerInvariant()
$sourceProbe=Probe-Audio -File $source
$script:Evidencias=@{('TestVideo01|fixture-192|'+$sourceHash)=@{qualidade='perdas_verificadas';bitrate_minimo_historico_kbps=192;origem='PCM sintetico local';historico='Codificado uma unica vez para fixture MP3192'}}
$proof=@{versao=1;video_id='TestVideo01';artista='AC/DC';musica='iTunes DJ';artista_musica_conferidos=$true;versao_conferida=$true;sem_vocais_conferido=$true;origem='arquivo_aprovacoes'}
$sha=[Security.Cryptography.SHA256]::Create()
try{$key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]::Join([char]31,@('1','AC/DC','iTunes DJ','https://www.youtube.com/watch?v=TestVideo01'))))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
$work=Join-Path $PSScriptRoot ('.runtime-intencao-reconciliacao-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $work
function New-RecoveryFixture([string]$Name,[bool]$Persist=$true){
 if($null -ne $script:Lock){$script:Lock.Dispose();$script:Lock=$null}
 $script:Out=Join-Path $work $Name;$script:Control=Join-Path $script:Out '.controle'
 $script:StateFile=Join-Path $script:Control 'estado.json'
 $fontes=Join-Path $script:Control 'fontes';$null=New-Item -ItemType Directory -Path $fontes
 $script:Lock=[IO.File]::Open((Join-Path $script:Control 'execucao.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 $ready=Join-Path $fontes 'source.mp3';$target=Join-Path $script:Out 'final.mp3'
 Copy-Item -LiteralPath $source -Destination $ready
 $row=[pscustomobject]@{Ordem='1';Artista='AC/DC';Musica='iTunes DJ';Link_YouTube='https://www.youtube.com/watch?v=TestVideo01';Tipo_link='Direto';Verificacao='Fixture';Observacoes='Fixture sintetica'}
 $record=New-Record -Row $row -Key $key
 $record.video_id='TestVideo01';$record.aprovacao_musical=$proof
 $audit=@{politica=$script:Policy;validado=$true;origem_sha256=$sourceHash;resultado_sha256=$sourceHash;origem_formato_id='fixture-192';origem=$sourceProbe}
 $snapshot=New-PublicationIntentSnapshot -Ready $ready -Target $target -Control $script:Control -Out $script:Out -VideoId 'TestVideo01' -Record $record -Audit $audit -Probe $sourceProbe
 $saved=Save-PublicationIntentFile -Snapshot $snapshot -Control $script:Control -Out $script:Out
 $name=[IO.Path]::GetFileName($saved.Path)
 $script:State=@{versao=1;videos=@{};buscas=@{};registros=@{canary=@{nota='historico preservado'}};publicacoes_pendentes=@{}}
 Save-State
 $script:State.publicacoes_pendentes[$name]=@{versao=1;arquivo=$name;sha256=$saved.Sha256;video_id='TestVideo01';registro_chave=$key}
 if($Persist){Save-State}
 return @{Name=$name;Ready=$ready;Target=$target;Intent=$saved.Path;IntentHash=$saved.Sha256}
}
try{
 $case=New-RecoveryFixture -Name 'not-persisted' -Persist $false
 $caught=$false
 try{$null=Invoke-PublicationRecovery -ReferenceName (('a'*64)+'xjson') -Control $script:Control -Out $script:Out}
 catch [ArgumentException]{if($_.Exception.Message -notmatch 'Nome'){throw};$caught=$true}
 if(-not $caught){throw 'Referencia com extensao nao literal foi aceita'}

 $caught=$false
 try{$null=Invoke-PublicationRecovery -ReferenceName $case.Name -Control $script:Control -Out $script:Out}catch [IO.InvalidDataException]{if($_.Exception.Message -notmatch 'persistida'){throw};$caught=$true}
 if(-not $caught -or (Test-Path -LiteralPath $case.Target)){throw 'Referencia nao persistida autorizou movimento'}
 $case=New-RecoveryFixture -Name 'no-lock'
 $script:Lock.Dispose();$script:Lock=$null;$caught=$false
 try{$null=Invoke-PublicationRecovery -ReferenceName $case.Name -Control $script:Control -Out $script:Out}catch [InvalidOperationException]{$caught=$true}
 if(-not $caught -or (Test-Path -LiteralPath $case.Target)){throw 'Lock nao exigido'}
 $case=New-RecoveryFixture -Name 'conflict'
 $script:State.videos.TestVideo01=@{artista='Outro';musica='iTunes DJ';arquivo='outro.mp3';sha256=('f'*64);aprovacao_musical=$proof}
 Save-State;$caught=$false
 try{$null=Invoke-PublicationRecovery -ReferenceName $case.Name -Control $script:Control -Out $script:Out}catch [IO.InvalidDataException]{if($_.Exception.Message -notmatch 'Conflito'){throw};$caught=$true}
 if(-not $caught -or $script:State.videos.TestVideo01.artista -cne 'Outro' -or (Test-Path -LiteralPath $case.Target)){throw 'Conflito sobrescrito'}
 $case=New-RecoveryFixture -Name 'save-failure'
 if($IsWindows){
  # Permite ler referencia persistida, mas impede Replace do estado APOS mover o audio.
  $stateLock=[IO.File]::Open($script:StateFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  $caught=$false
  try{
   try{$null=Invoke-PublicationRecovery -ReferenceName $case.Name -Control $script:Control -Out $script:Out}catch{
    $failure=$_.Exception;while($null -ne $failure.InnerException){$failure=$failure.InnerException}
    if($failure -isnot [IO.IOException]){throw};$caught=$true
   }
  }finally{$stateLock.Dispose()}
  $disk=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
  if(-not $caught -or (Test-Path -LiteralPath $case.Ready) -or -not (Test-Path -LiteralPath $case.Target) -or $disk.videos.Count -ne 0 -or -not $disk.publicacoes_pendentes.ContainsKey($case.Name)){throw 'Janela Move->State nao preservou referencia/arquivo'}
  $script:State=$disk
 }else{
  [IO.File]::Move($case.Ready,$case.Target)
  Write-Output 'FALHA_SAVE_POS_MOVE_NAO_TESTADA_NESTE_SO'
 }
 $result=Invoke-PublicationRecovery -ReferenceName $case.Name -Control $script:Control -Out $script:Out
 $disk=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
 if($result.Status -cne 'reconciliada' -or $result.Action -cne 'restore_state' -or $disk.videos.TestVideo01.sha256 -cne $sourceHash -or $disk.videos.TestVideo01.auditoria.origem_sha256 -cne $sourceHash -or $disk.registros[$key].resultado -cne 'existente' -or $disk.publicacoes_pendentes.Count -ne 0 -or $disk.registros.canary.nota -cne 'historico preservado'){throw 'Retomada nao reconciliou estado'}
 if(-not $disk.videos.TestVideo01.aprovacao_musical.sem_vocais_conferido -or $disk.videos.TestVideo01.publicacao_intencao.sha256 -cne $case.IntentHash -or (Get-FileHash -LiteralPath $case.Intent).Hash.ToLowerInvariant() -cne $case.IntentHash){throw 'Prova/rastro da intencao perdido'}
 $stateHash=(Get-FileHash -LiteralPath $script:StateFile).Hash
 $again=Invoke-PublicationRecovery -ReferenceName $case.Name -Control $script:Control -Out $script:Out
 if($again.Status -cne 'sem_pendencia' -or (Get-FileHash -LiteralPath $script:StateFile).Hash -cne $stateHash -or (Get-FileHash -LiteralPath $case.Target).Hash.ToLowerInvariant() -cne $sourceHash){throw 'Repeticao nao foi idempotente'}
 $case=New-RecoveryFixture -Name 'publish'
 $result=Invoke-PublicationRecovery -ReferenceName $case.Name -Control $script:Control -Out $script:Out
 $disk=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
 if($result.Action -cne 'publish' -or $disk.registros[$key].resultado -cne 'baixado' -or $disk.publicacoes_pendentes.Count -ne 0 -or (Test-Path -LiteralPath $case.Ready) -or (Get-FileHash -LiteralPath $case.Target).Hash.ToLowerInvariant() -cne $sourceHash){throw 'Publicacao retomada falhou'}
 if((Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant() -cne $sourceHash){throw 'Fonte original alterada'}
 Write-Output 'INTENCAO_RECONCILIACAO_PASS'
}finally{if($null -ne $script:Lock){$script:Lock.Dispose();$script:Lock=$null}}
