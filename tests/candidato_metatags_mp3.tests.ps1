#requires -Version 7.0
param([string]$HelperPath='',[switch]$SkipNative)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$root=Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($HelperPath)){$HelperPath=Join-Path $root 'candidato_metatags_mp3.ps1'}
. (Join-Path $root 'argumentos_metatags_mp3.ps1')
$t=$null;$e=$null
$null=[Management.Automation.Language.Parser]::ParseFile($HelperPath,[ref]$t,[ref]$e)
if($e.Count){throw 'Helper com sintaxe invalida'}
. $HelperPath
$dir=Join-Path $PSScriptRoot ('.runtime-tag-candidate-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($dir)
$src=Join-Path $dir 'source.mp3'
[IO.File]::WriteAllBytes($src,[byte[]](1,2,3,4,5))
$sourceHash=(Get-FileHash -LiteralPath $src).Hash
$ffmpeg=Join-Path $root 'ffmpeg.exe'
$ffprobe=Join-Path $root 'ffprobe.exe'
if(-not [IO.File]::Exists($ffmpeg)){throw 'FFmpeg do teste ausente'}
$script:Calls=0;$script:Mode='success';$script:MutateInput=$null
function Invoke-Ytdlp {
 param([string]$Executable,[string[]]$Arguments,[int]$TimeoutSeconds)
 $script:Calls++;$script:LastExecutable=$Executable;$script:LastArgv=$Arguments.Clone();$script:LastTimeout=$TimeoutSeconds
 if($script:Mode -eq 'native'){
  $r=Invoke-CapturedTestProcess -Program $Executable -Arguments $Arguments -TimeoutMs 30000
  return @{code=$r.ExitCode;out=$r.Stdout;err=$r.Stderr;timeout=$false}
 }
 if($null -ne $script:MutateInput){$script:MutateInput.title='caller_changed'}
 $script:LastMode=$script:Mode
 $target=$Arguments[-1]
 switch($script:Mode){
  'timeout' {[IO.File]::WriteAllBytes($target,[byte[]](8,9));return @{timeout=$true;code=-1;out='';err='timeout_fixture'}}
  'nonzero' {[IO.File]::WriteAllBytes($target,[byte[]](8,9));return @{timeout=$false;code=7;out='';err='error_fixture'}}
  'missing' {return @{timeout=$false;code=0;out='';err=''}}
  'empty' {[IO.File]::WriteAllBytes($target,[byte[]]@());return @{timeout=$false;code=0;out='';err=''}}
  default {[IO.File]::WriteAllBytes($target,[byte[]](6,7,8));return @{timeout=$false;code=0;out='';err=''}}
 }
}
$failed=0;$total=0
function Check-CandidateCase([string]$Name,[scriptblock]$Body){
 $script:total++;$script:Calls=0;$script:Mode='success';$script:MutateInput=$null
 try{. $Body;if((Get-FileHash -LiteralPath $src).Hash -cne $sourceHash){throw 'Fonte canario alterada'};'PASS '+$Name}catch{$script:failed++;'FAIL '+$Name+': '+$_.Exception.Message}
}
function Assert-CandidateThrows([scriptblock]$Body,[type]$Type){
 $caught=$false
 try{. $Body}catch{$ex=$_.Exception;while($null -ne $ex.InnerException){$ex=$ex.InnerException};if($ex -isnot $Type){throw};$caught=$true}
 if(-not $caught){throw 'Excecao esperada ausente'}
}
Check-CandidateCase 'mock_success_snapshot' {
 $out=Join-Path $dir 'success.mp3';$u=@{title=' Título iTunes '}
 $script:MutateInput=$u
 $r=New-Mp3EditorialTagCandidate -File $src -Output $out -Updates $u -Ffmpeg $ffmpeg
 if($r -isnot [pscustomobject] -or $r.Validated -isnot [bool] -or $r.Validated -or $script:Calls -ne 1 -or $script:LastTimeout -ne 180){throw 'Retorno/execucao invalido'}
 if([object]::ReferenceEquals($u,$r.Updates) -or -not [string]::Equals($r.Updates.title,' Título iTunes ',[StringComparison]::Ordinal)){throw 'Updates nao e snapshot independente'}
 if(-not [string]::Equals($script:LastArgv[16],'title= Título iTunes ',[StringComparison]::Ordinal) -or $script:LastArgv[-2] -cne '-n'){throw 'Argv diferente do pedido'}
 if(-not [string]::Equals($r.SourcePath,$src,[StringComparison]::Ordinal) -or -not [string]::Equals($r.CandidatePath,$out,[StringComparison]::Ordinal) -or $script:LastExecutable -cne $ffmpeg){throw 'Paths incorretos'}
}
$invalid=@(
 @{Name='updates_null';Changes=@{Updates=$null};Type=[ArgumentException]}
 @{Name='updates_empty';Changes=@{Updates=@{}};Type=[ArgumentException]}
 @{Name='invalid_key';Changes=@{Updates=@{Title='X'}};Type=[ArgumentException]}
 @{Name='array_value';Changes=@{Updates=@{title=@('A','B')}};Type=[ArgumentException]}
 @{Name='source_relative';Changes=@{File='relative.mp3'};Type=[ArgumentException]}
 @{Name='output_relative';Changes=@{Output='relative.mp3'};Type=[ArgumentException]}
 @{Name='same_path';Changes=@{Output=$src};Type=[ArgumentException]}
 @{Name='source_missing';Changes=@{File=(Join-Path $dir 'missing.mp3')};Type=[IO.FileNotFoundException]}
 @{Name='executable_missing';Changes=@{Ffmpeg=(Join-Path $dir 'missing.exe')};Type=[IO.FileNotFoundException]}
 @{Name='executable_relative';Changes=@{Ffmpeg='ffmpeg.exe'};Type=[ArgumentException]}
 @{Name='executable_empty';Changes=@{Ffmpeg=''};Type=[ArgumentException]}
 @{Name='executable_null';Changes=@{Ffmpeg=$null};Type=[ArgumentException]}
 @{Name='executable_whitespace';Changes=@{Ffmpeg=' '};Type=[ArgumentException]}
)
foreach($case in $invalid){
 Check-CandidateCase $case.Name {
  $out=Join-Path $dir ($case.Name+'.mp3');$call=@{File=$src;Output=$out;Updates=@{title='X'};Ffmpeg=$ffmpeg}
  foreach($key in $case.Changes.Keys){$call[$key]=$case.Changes[$key]}
  Assert-CandidateThrows {New-Mp3EditorialTagCandidate @call} $case.Type
  if($script:Calls -ne 0 -or [IO.File]::Exists($out)){throw 'Precondicao executou processo/criou output'}
 }
}
Check-CandidateCase 'existing_file_preserved' {
 $out=Join-Path $dir 'existing.mp3';[IO.File]::WriteAllBytes($out,[byte[]](55,66));$h=(Get-FileHash -LiteralPath $out).Hash
 Assert-CandidateThrows {New-Mp3EditorialTagCandidate -File $src -Output $out -Updates @{title='X'} -Ffmpeg $ffmpeg} ([IO.IOException])
 if($script:Calls -ne 0 -or (Get-FileHash -LiteralPath $out).Hash -cne $h){throw 'Output existente alterado'}
}
Check-CandidateCase 'existing_directory_preserved' {
 $out=Join-Path $dir 'existing-dir.mp3';$null=[IO.Directory]::CreateDirectory($out)
 Assert-CandidateThrows {New-Mp3EditorialTagCandidate -File $src -Output $out -Updates @{title='X'} -Ffmpeg $ffmpeg} ([IO.IOException])
 if($script:Calls -ne 0 -or -not [IO.Directory]::Exists($out)){throw 'Diretorio existente alterado'}
}
foreach($scenarioMode in @('timeout','nonzero','missing','empty')){
 Check-CandidateCase ('failure_'+$scenarioMode) {
  $script:Mode=$scenarioMode;$out=Join-Path $dir ($scenarioMode+'.mp3')
  $type=switch($scenarioMode){'timeout'{[TimeoutException]};'nonzero'{[InvalidOperationException]};default{[IO.InvalidDataException]}}
  Assert-CandidateThrows {New-Mp3EditorialTagCandidate -File $src -Output $out -Updates @{title='X'} -Ffmpeg $ffmpeg} $type
  if($script:Calls -ne 1 -or $script:LastMode -cne $scenarioMode){throw 'Quantidade de invocacoes ou modo incorreto'}
  if($scenarioMode -in @('timeout','nonzero') -and (-not [IO.File]::Exists($out) -or (Get-Item -LiteralPath $out).Length -ne 2)){throw 'Parcial foi removido/alterado'}
  if($scenarioMode -eq 'empty' -and (-not [IO.File]::Exists($out) -or (Get-Item -LiteralPath $out).Length -ne 0)){throw 'Candidato vazio foi removido'}
 }
}
if(-not $SkipNative){
 . (Join-Path $root 'tests/processo_capturado.ps1')
 . (Join-Path $root 'editorial_audio.ps1')
 Check-CandidateCase 'native_stream_copy' {
  $script:Mode='native'
  $nativeSource=Join-Path $dir 'native-source.mp3';$nativeOutput=Join-Path $dir 'native-candidate.mp3'
  $generated=Invoke-CapturedTestProcess -Program $ffmpeg -Arguments @('-nostdin','-v','error','-f','lavfi','-i','anoisesrc=sample_rate=44100:duration=2:seed=4321','-ac','2','-c:a','libmp3lame','-b:a','128k','-threads','1','-id3v2_version','3','-metadata','keep_tag=Sentinela ç','-metadata','marcador_coletanea=Grupo','-n',$nativeSource) -TimeoutMs 30000
  if($generated.ExitCode -ne 0){throw ('Fixture nativa: '+$generated.Stderr)}
  $nativeHash=(Get-FileHash -LiteralPath $nativeSource).Hash
  $updates=@{artist='Artista é DJ';title='Faixa iTunes';album='Coletânea';track='003';composer='AC/DC'}
  $r=New-Mp3EditorialTagCandidate -File $nativeSource -Output $nativeOutput -Updates $updates -Ffmpeg $ffmpeg
  if($script:Calls -ne 1 -or $r.Validated -isnot [bool] -or $r.Validated){throw 'Candidato foi declarado validado/executado mais de uma vez'}
  $before=Get-AudioMetadataSnapshot -File $nativeSource -Ffprobe $ffprobe
  $after=Get-AudioMetadataSnapshot -File $nativeOutput -Ffprobe $ffprobe
  foreach($key in $updates.Keys){if(-not [string]::Equals([string]$after.format.tags.$key,[string]$updates[$key],[StringComparison]::Ordinal)){throw ('Tag nativa divergente: '+$key)}}
  foreach($p in $before.format.tags.PSObject.Properties){if(-not $updates.ContainsKey($p.Name) -and -not [string]::Equals([string]$after.format.tags.($p.Name),[string]$p.Value,[StringComparison]::Ordinal)){throw ('Tag nao solicitada alterada: '+$p.Name)}}
  $h1=Get-CompressedAudioHash -File $nativeSource -Ffmpeg $ffmpeg
  $h2=Get-CompressedAudioHash -File $nativeOutput -Ffmpeg $ffmpeg
  if($h1 -cne $h2 -or (Get-FileHash -LiteralPath $nativeSource).Hash -cne $nativeHash){throw 'Fonte/fluxo de audio mudou'}
  [IO.File]::WriteAllText((Join-Path $dir 'native-result.json'),(@{Source=$nativeSource;Candidate=$nativeOutput;SourceSha256=$nativeHash;ElementarySha256=$h1;Validated=$r.Validated;Tags=$after.format.tags}|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
 }
}
if($failed){throw ('MP3_TAG_CANDIDATE_FAILURES='+$failed)}
'MP3_TAG_CANDIDATE_PASS cases='+$total+' native='+(-not $SkipNative)+' artifacts='+$dir
