#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1.0
$repo=Split-Path -Parent $PSScriptRoot
$script:Root=$repo
$script:Exe=Join-Path $repo 'yt-dlp.exe'
$script:Ffmpeg=Join-Path $repo 'ffmpeg.exe'
$script:Ffprobe=Join-Path $repo 'ffprobe.exe'
$script:Policy='fidelidade-128-v1'
. (Join-Path $repo 'execucao_unica.ps1')
. (Join-Path $repo 'publicacao_pendente.ps1')
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'baixar_audios_ytdlp.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Sintaxe de producao invalida'}
foreach($name in @('Invoke-Ytdlp','Probe-Audio','Test-FinalAudio','Test-SourceEvidence')){
 $defs=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
 if($defs.Count -ne 1){throw 'Funcao ambigua'}
 . ([scriptblock]::Create($defs[0].Extent.Text))
}
# Historico/prova desta fixture sao declaracoes sinteticas; nenhum video real e homologado.
$generated=@(& (Join-Path $repo 'tests/criar_fixture_marcador_mp3.ps1'))|Out-String
$receipt=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText((ConvertFrom-PublicationJson -Json $generated).receipt_path))
$source=$receipt.fixture.sourcepath
$sourceHash=$receipt.fixture.hash.ToLowerInvariant()
if((Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant() -cne $sourceHash){throw 'Fonte diverge do recibo independente'}
$sourceProbe=Probe-Audio -File $source
$script:Evidencias=@{('TestVideo01|fixture-192|'+$sourceHash)=@{qualidade='perdas_verificadas';bitrate_minimo_historico_kbps=192;origem='PCM sintetico local codificado uma unica vez';historico='Fixture FFmpeg, nao video remoto'}}
$proof=@{versao=1;video_id='TestVideo01';artista='AC/DC';musica='iTunes DJ';artista_musica_conferidos=$true;versao_conferida=$true;sem_vocais_conferido=$true;origem='arquivo_aprovacoes'}
$sha=[Security.Cryptography.SHA256]::Create()
try{$key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]::Join([char]31,@('1','AC/DC','iTunes DJ','https://www.youtube.com/watch?v=TestVideo01'))))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
$work=Join-Path $PSScriptRoot ('.runtime-intencao-plano-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $work
function New-PlanFixture([string]$Name,[hashtable]$Approval=$proof,[string]$Policy='fidelidade-128-v1',[string]$InputFile=$source){
 $out=Join-Path $work $Name;$control=Join-Path $out '.controle';$fontes=Join-Path $control 'fontes'
 $null=New-Item -ItemType Directory -Path $fontes
 $ready=Join-Path $fontes 'source.mp3';$target=Join-Path $out 'final.mp3'
 Copy-Item -LiteralPath $InputFile -Destination $ready
 $record=@{chave=$key;ordem='1';artista='AC/DC';musica='iTunes DJ';url_original='https://www.youtube.com/watch?v=TestVideo01';video_id='TestVideo01';aprovacao_musical=$Approval}
 $audit=@{politica=$Policy;validado=$true;origem_sha256=$sourceHash;resultado_sha256=(Get-FileHash -LiteralPath $ready).Hash.ToLowerInvariant();origem_formato_id='fixture-192';origem=$sourceProbe}
 $snapshot=New-PublicationIntentSnapshot -Ready $ready -Target $target -Control $control -Out $out -VideoId 'TestVideo01' -Record $record -Audit $audit -Probe (Probe-Audio -File $ready)
 $saved=Save-PublicationIntentFile -Snapshot $snapshot -Control $control -Out $out
 return @{Args=@{Path=$saved.Path;ExpectedSha256=$saved.Sha256;Control=$control;Out=$out};Ready=$ready;Target=$target}
}
$main=New-PlanFixture -Name 'valid'
$arguments=$main.Args
$plan=Get-PublicationRecoveryPlan @arguments
if($plan.Status -cne 'plano_validado_sem_efeitos' -or $plan.Action -cne 'publish' -or $plan.Path -cne $main.Ready -or $plan.Data.sha256 -cne $sourceHash -or $plan.Probe.codec -cne 'mp3' -or $plan.Probe.bitrate_medido_kbps -lt 128 -or (Test-Path -LiteralPath $main.Target)){throw 'Plano de publicacao invalido ou teve efeitos'}
$badProof=$proof.Clone();$badProof.sem_vocais_conferido=$false
$proofCase=New-PlanFixture -Name 'proof' -Approval $badProof
$policyCase=New-PlanFixture -Name 'policy' -Policy 'policy-invalida'
$low=Join-Path $work 'low96.mp3'
$run=Invoke-Ytdlp -Executable $script:Ffmpeg -Arguments @('-nostdin','-v','error','-f','lavfi','-i','anoisesrc=sample_rate=44100:duration=2:seed=8','-ac','2','-c:a','libmp3lame','-b:a','96k','-n',$low)
if($run.code -ne 0 -or $run.timeout){throw 'Fixture 96k falhou'}
$qualityCase=New-PlanFixture -Name 'quality' -InputFile $low
$keyCase=New-PlanFixture -Name 'key'
$data=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($keyCase.Args.Path))
$data.registro.url_original='https://www.youtube.com/watch?v=OtherVideo1'
$body=[Text.UTF8Encoding]::new($false).GetBytes(($data|ConvertTo-Json -Depth 25))
[IO.File]::WriteAllBytes($keyCase.Args.Path,$body)
$sha=[Security.Cryptography.SHA256]::Create()
try{$keyCase.Args.ExpectedSha256=[BitConverter]::ToString($sha.ComputeHash($body)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
foreach($case in @(@{Args=$proofCase.Args;Message='Aprovacao'},@{Args=$policyCase.Args;Message='Politica'},@{Args=$qualityCase.Args;Message='Qualidade'},@{Args=$keyCase.Args;Message='Chave'})){
 $caught=$false;$arguments=$case.Args
 try{$null=Get-PublicationRecoveryPlan @arguments}catch [IO.InvalidDataException]{if($_.Exception.Message.IndexOf($case.Message,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw};$caught=$true}
 if(-not $caught){throw ('Plano aceitou negativo: '+$case.Message)}
}
$savedEvidence=$script:Evidencias
try{
 $script:Evidencias=@{};$arguments=$main.Args;$caught=$false
 try{$null=Get-PublicationRecoveryPlan @arguments}catch [IO.InvalidDataException]{if($_.Exception.Message -notmatch 'Procedencia'){throw};$caught=$true}
 if(-not $caught){throw 'Plano dispensou evidencia atual'}
}finally{$script:Evidencias=$savedEvidence}
[IO.File]::WriteAllBytes($main.Target,[byte[]]@(9,8,7))
$collisionHash=(Get-FileHash -LiteralPath $main.Target).Hash
$caught=$false;$arguments=$main.Args
try{$null=Get-PublicationRecoveryPlan @arguments}catch [IO.InvalidDataException]{if($_.Exception.Message -notmatch 'Hash'){throw};$caught=$true}
if(-not $caught -or (Get-FileHash -LiteralPath $main.Target).Hash -cne $collisionHash){throw 'Plano sobrescreveu colisao'}
[IO.File]::Move($main.Target,(Join-Path $work 'collision-preserved.bin'))
[IO.File]::Move($main.Ready,$main.Target)
$plan=Get-PublicationRecoveryPlan @arguments
if($plan.Action -cne 'restore_state' -or $plan.Path -cne $main.Target -or (Test-Path -LiteralPath $main.Ready) -or (Get-FileHash -LiteralPath $main.Target).Hash.ToLowerInvariant() -cne $sourceHash -or (Test-Path -LiteralPath (Join-Path $main.Args.Control 'estado.json'))){throw 'Plano pos-publicacao invalido ou escreveu estado'}
if((Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant() -cne $sourceHash){throw 'Fonte original alterada'}
Write-Output 'INTENCAO_PLANO_PASS'
