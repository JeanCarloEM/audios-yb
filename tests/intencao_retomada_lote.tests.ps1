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

. (Join-Path $repo 'referencia_publicacao.ps1')
# MP3 real sintetico e declaracoes de fixture; nao comprova procedencia/identidade remota.
$blockedState=$null
try{
 # Dois checkpoints no MESMO destino; corromper o primeiro em ordem Ordinal obriga continuar.
 $case=New-RecoveryFixture -Name 'batch-mixed'
 $first=Read-PublicationIntentFile -Path $case.Intent -ExpectedSha256 $case.IntentHash -Control $script:Control
 $secondRecord=ConvertFrom-PublicationJson -Json ($first.Data.registro|ConvertTo-Json -Depth 25 -WarningAction Stop)
 $secondRecord.video_id='TestVideo02';$secondRecord.url_original='https://www.youtube.com/watch?v=TestVideo02'
 $secondRecord.aprovacao_musical.video_id='TestVideo02'
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$secondRecord.chave=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]::Join([char]31,@($secondRecord.ordem,$secondRecord.artista,$secondRecord.musica,$secondRecord.url_original))))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
 $secondReady=Join-Path (Join-Path $script:Control 'fontes') 'source2.mp3'
 Copy-Item -LiteralPath $source -Destination $secondReady
 $snapshot=New-PublicationIntentSnapshot -Ready $secondReady -Target (Join-Path $script:Out 'final2.mp3') -Control $script:Control -Out $script:Out -VideoId 'TestVideo02' -Record $secondRecord -Audit $first.Data.auditoria -Probe $sourceProbe
 $saved=Save-PublicationIntentFile -Snapshot $snapshot -Control $script:Control -Out $script:Out
 $secondRef=New-PublicationReference -VideoId 'TestVideo02' -RecordKey $secondRecord.chave -IntentSha256 $saved.Sha256
 $script:State.publicacoes_pendentes[$secondRef.arquivo]=$secondRef
 $script:Evidencias[('TestVideo02|fixture-192|'+$sourceHash)]=$script:Evidencias[('TestVideo01|fixture-192|'+$sourceHash)].Clone()
 Save-State
 $names=[string[]]@($script:State.publicacoes_pendentes.Keys);[Array]::Sort($names,[StringComparer]::Ordinal)
 $bad=$names[0];$good=$names[1]
 $badRef=$script:State.publicacoes_pendentes[$bad].Clone()
 $goodRef=$script:State.publicacoes_pendentes[$good].Clone()
 $badPath=Join-Path (Join-Path $script:Control 'publicacoes_pendentes') $bad
 $badJournal=Read-PublicationIntentFile -Path $badPath -ExpectedSha256 $badRef.sha256 -Control $script:Control
 $badReady=Join-Path $script:Control $badJournal.Data.pronto_relativo
 $badTarget=Join-Path $script:Out $badJournal.Data.arquivo
 $script:State.publicacoes_pendentes[$bad].sha256='0'*64;Save-State
 $batch=Resume-PendingPublications -Control $script:Control -Out $script:Out
 if($batch.Recovered.Count -ne 1 -or $batch.Unresolved.Count -ne 1 -or -not $batch.PreserveAllFiles -or $batch.Recovered[0].VideoId -cne $goodRef.video_id -or -not $script:State.publicacoes_pendentes.ContainsKey($bad) -or $script:State.publicacoes_pendentes.Count -ne 1){throw 'Falha do primeiro checkpoint impediu o segundo ou perdeu pendencia'}
 if(@($batch.RecordKeys|Where-Object {[string]::Equals($_,$badRef.registro_chave,[StringComparison]::Ordinal)}).Count -ne 1 -or @($batch.VideoIds|Where-Object {[string]::Equals($_,$badRef.video_id,[StringComparison]::Ordinal)}).Count -ne 1){throw 'Identidades pendentes nao foram devolvidas'}
 if(-not [IO.File]::Exists($badReady) -or [IO.File]::Exists($badTarget) -or (Get-FileHash -LiteralPath $badPath).Hash.ToLowerInvariant() -cne $badRef.sha256 -or $script:State.registros.canary.nota -cne 'historico preservado'){throw 'Pendencia/historico foi destruido'}
 # Auditoria nao publica Ready e devolve nome protegido conhecido sem alterar estado.
 $case=New-RecoveryFixture -Name 'batch-audit'
 $before=(Get-FileHash -LiteralPath $script:StateFile).Hash
 $batch=Resume-PendingPublications -Control $script:Control -Out $script:Out -AuditOnly
 if($batch.Recovered.Count -ne 0 -or $batch.Unresolved.Count -ne 1 -or $batch.PreserveAllFiles -or @($batch.ProtectedFiles|Where-Object {[string]::Equals($_,'final.mp3',[StringComparison]::Ordinal)}).Count -ne 1 -or (Get-FileHash -LiteralPath $script:StateFile).Hash -cne $before -or -not [IO.File]::Exists($case.Ready) -or [IO.File]::Exists($case.Target)){throw 'Auditoria publicou ou nao protegeu o checkpoint'}
 # Journal legivel, mas evidencia atual removida: proteger somente o nome conhecido.
 $script:Evidencias.Remove(('TestVideo01|fixture-192|'+$sourceHash))
 $batch=Resume-PendingPublications -Control $script:Control -Out $script:Out
 if($batch.Recovered.Count -ne 0 -or $batch.Unresolved.Count -ne 1 -or $batch.PreserveAllFiles -or -not ($batch.ProtectedFiles -contains 'final.mp3') -or (Get-FileHash -LiteralPath $script:StateFile).Hash -cne $before -or -not [IO.File]::Exists($case.Ready) -or [IO.File]::Exists($case.Target)){throw 'Falha semantica perdeu nome protegido ou alterou arquivos'}
 $script:Evidencias[('TestVideo01|fixture-192|'+$sourceHash)]=@{qualidade='perdas_verificadas';bitrate_minimo_historico_kbps=192;origem='PCM sintetico local';historico='Codificado uma unica vez para fixture MP3192'}
 # Falha REAL Save1 apos Move: proteger Target e permitir retomada pelo disco.
 $case=New-RecoveryFixture -Name 'batch-post-move-io'
 $before=(Get-FileHash -LiteralPath $script:StateFile).Hash
 $blockedState=[IO.File]::Open($script:StateFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 $batch=Resume-PendingPublications -Control $script:Control -Out $script:Out
 if($batch.Recovered.Count -ne 0 -or $batch.Unresolved.Count -ne 1 -or -not ($batch.ProtectedFiles -contains 'final.mp3') -or (Get-FileHash -LiteralPath $script:StateFile).Hash -cne $before -or [IO.File]::Exists($case.Ready) -or -not [IO.File]::Exists($case.Target)){throw 'IO apos Move nao ficou recuperavel/protegido'}
 $blockedState.Dispose();$blockedState=$null
 $script:State=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
 $batch=Resume-PendingPublications -Control $script:Control -Out $script:Out
 if($batch.Recovered.Count -ne 1 -or $batch.Recovered[0].Action -cne 'restore_state' -or $batch.Unresolved.Count -ne 0 -or $batch.ProtectedFiles.Count -ne 0 -or $batch.PreserveAllFiles -or $script:State.publicacoes_pendentes.Count -ne 0 -or (Get-FileHash -LiteralPath $case.Target).Hash.ToLowerInvariant() -cne $sourceHash){throw 'Retomada pelo disco falhou'}
 if((Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant() -cne $sourceHash){throw 'Fonte original alterada'}
 'PENDING_PUBLICATION_BATCH_PASS: continuidade, auditoria, protecao e IO real apos Move'
 $global:LASTEXITCODE=0
}finally{
 if($null -ne $blockedState){$blockedState.Dispose()}
 if($null -ne $script:Lock){$script:Lock.Dispose();$script:Lock=$null}
}
