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
# Reusa somente preparacao da fixture existente; identidade/procedencia sao declaracoes sinteticas.
# Nenhum teste antigo e executado. O arquivo MP3 da fixture e real; nao ha transporte remoto.
$blockedState=$null
try{
 $case=New-RecoveryFixture -Name 'register-plan' -Persist $false
 $script:State=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
 $stateBefore=(Get-FileHash -LiteralPath $script:StateFile).Hash
 $script:Lock.Dispose();$script:Lock=$null
 $caught=$false
 try{$null=Register-PublicationReference -Path $case.Intent -ExpectedSha256 $case.IntentHash -Control $script:Control -Out $script:Out}
 catch [InvalidOperationException]{$caught=$true}
 if(-not $caught -or (Get-FileHash -LiteralPath $script:StateFile).Hash -cne $stateBefore){throw 'Registro sem lock foi aceito ou alterou disco'}
 $script:Lock=[IO.File]::Open((Join-Path $script:Control 'execucao.lock'),[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 $caught=$false
 try{$null=Register-PublicationReference -Path $case.Intent -ExpectedSha256 ('0'*64) -Control $script:Control -Out $script:Out}
 catch [IO.InvalidDataException]{$caught=$true}
 if(-not $caught -or (Get-FileHash -LiteralPath $script:StateFile).Hash -cne $stateBefore -or $script:State.publicacoes_pendentes.Count -ne 0){throw 'Hash externo errado foi aceito ou alterou estado'}
 $blockedState=[IO.File]::Open($script:StateFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 $caught=$false
 try{$null=Register-PublicationReference -Path $case.Intent -ExpectedSha256 $case.IntentHash -Control $script:Control -Out $script:Out}
 catch [IO.IOException]{$caught=$true}
 if(-not $caught){throw 'Estado bloqueado foi tratado como sucesso'}
 $disk=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
 if((Get-FileHash -LiteralPath $script:StateFile).Hash -cne $stateBefore -or $disk.publicacoes_pendentes.Count -ne 0 -or $disk.registros.canary.nota -cne 'historico preservado'){throw 'Falha IO alterou estado persistido'}
 if(-not [IO.File]::Exists($case.Ready) -or [IO.File]::Exists($case.Target) -or (Get-FileHash -LiteralPath $case.Intent).Hash.ToLowerInvariant() -cne $case.IntentHash){throw 'Falha IO moveu fonte ou alterou journal'}
 $blockedState.Dispose();$blockedState=$null
 # Reconciliar memoria pelo disco apos falha antes de repetir apenas a gravacao da referencia.
 $script:State=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
 $reference=Register-PublicationReference -Path $case.Intent -ExpectedSha256 $case.IntentHash -Control $script:Control -Out $script:Out
 $disk=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile))
 if($reference.versao -ne 1 -or -not [string]::Equals($reference.arquivo,$case.Name,[StringComparison]::Ordinal) -or -not [string]::Equals($reference.sha256,$case.IntentHash,[StringComparison]::Ordinal) -or -not [string]::Equals($reference.video_id,'TestVideo01',[StringComparison]::Ordinal) -or -not [string]::Equals($reference.registro_chave,$key,[StringComparison]::Ordinal)){throw 'Referencia registrada diverge do recibo externo'}
 foreach($field in @('versao','arquivo','sha256','video_id','registro_chave')){if(-not [string]::Equals([string]$disk.publicacoes_pendentes[$case.Name][$field],[string]$reference[$field],[StringComparison]::Ordinal)){throw ('Disco diverge: '+$field)}}
 if($disk.registros.canary.nota -cne 'historico preservado' -or $disk.videos.Count -ne 0 -or $disk.buscas.Count -ne 0){throw 'Registro alterou historico ou publicou metadados de video'}
 $reference.sha256='0'*64
 if($script:State.publicacoes_pendentes[$case.Name].sha256 -cne $case.IntentHash){throw 'Retorno nao e isolado'}
 $stateAfter=(Get-FileHash -LiteralPath $script:StateFile).Hash
 $caught=$false
 try{$null=Register-PublicationReference -Path $case.Intent -ExpectedSha256 $case.IntentHash -Control $script:Control -Out $script:Out}
 catch [InvalidOperationException]{$caught=$true}
 if(-not $caught -or (Get-FileHash -LiteralPath $script:StateFile).Hash -cne $stateAfter){throw 'Referencia duplicada sobrescrita'}
 if(-not [IO.File]::Exists($case.Ready) -or [IO.File]::Exists($case.Target) -or (Get-FileHash -LiteralPath $case.Intent).Hash.ToLowerInvariant() -cne $case.IntentHash -or (Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant() -cne $sourceHash){throw 'Registro alterou fonte, journal ou destino'}
 'PUBLICATION_REFERENCE_REGISTRATION_PASS: disco confirmado; quatro rejeicoes; sem Move; MP3 sintetico'
 $global:LASTEXITCODE=0
}finally{
 if($null -ne $blockedState){$blockedState.Dispose()}
 if($null -ne $script:Lock){$script:Lock.Dispose();$script:Lock=$null}
}
