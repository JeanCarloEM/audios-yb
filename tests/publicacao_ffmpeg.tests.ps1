#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'publicacao_ffmpeg.ps1')
$checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Publicacao invalida aceita'}
$root=Join-Path $PSScriptRoot ('.runtime-publish-['+[guid]::NewGuid().ToString('N')+']');[void][IO.Directory]::CreateDirectory($root)
$sourcePath=Join-Path $root 'source[1].exe';[IO.File]::WriteAllBytes($sourcePath,[byte[]](97,98,99))
$sentinel=Join-Path $root 'keep.txt';[IO.File]::WriteAllText($sentinel,'preservar')
$sha='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
$source=[IO.File]::Open($sourcePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try{
 foreach($tool in @('ffmpeg','ffprobe')){
  $target=Join-Path $root ($tool+'.exe');$source.Position=2
  $r=Publish-FfmpegExecutable -RootDirectory $root -SourceStream $source -Tool $tool -ExpectedSize ([long]3) -ExpectedSha256 $sha
  Assert ($r -is [hashtable] -and $r.Count -eq 4 -and $r.status -ceq 'published' -and $r.target_path -ceq $target -and $r.size -is [long] -and $r.size -eq 3 -and $r.sha256 -ceq $sha) 'Recibo published'
  Assert ([IO.File]::ReadAllText($target) -ceq 'abc' -and $source.CanRead -and $source.Position -eq 2) 'Bytes/callerownership/Position'
  $r=Publish-FfmpegExecutable $root $source $tool ([long]3) $sha
  Assert ($r.status -ceq 'existing' -and [IO.File]::ReadAllText($target) -ceq 'abc' -and $source.Position -eq 2) 'Idempotencia existing'
  [IO.File]::Delete($target)
 }
 $ffmpeg=Join-Path $root 'ffmpeg.exe';[IO.File]::WriteAllText($ffmpeg,'divergente')
 MustFail {Publish-FfmpegExecutable $root $source 'ffmpeg' ([long]3) $sha}
 Assert ([IO.File]::ReadAllText($ffmpeg) -ceq 'divergente') 'Nunca substitui divergente'
 [IO.File]::WriteAllText($ffmpeg,'xyz')
 MustFail {Publish-FfmpegExecutable $root $source 'ffmpeg' ([long]3) $sha}
 Assert ([IO.File]::ReadAllText($ffmpeg) -ceq 'xyz') 'Preserva divergente mesmo tamanho'
 [IO.File]::Delete($ffmpeg)
 $ffprobe=Join-Path $root 'ffprobe.exe';[void][IO.Directory]::CreateDirectory($ffprobe)
 MustFail {Publish-FfmpegExecutable $root $source 'ffprobe' ([long]3) $sha}
 Assert ([IO.Directory]::Exists($ffprobe)) 'Preserva diretorio destino'
 [IO.Directory]::Delete($ffprobe,$false)
 MustFail {Publish-FfmpegExecutable $root $source 'ffmpeg' ([long]3) ('0'*64)}
 Assert (![IO.File]::Exists($ffmpeg) -and @([IO.Directory]::EnumerateFiles($root,'.ffmpeg.publish.*.tmp')).Count -eq 0 -and $source.Position -eq 2 -and $source.CanRead) 'Hash mismatch cleanup'
 foreach($size in @($null,3,'3',[long]0,[long]4,[long]536870913)){MustFail {Publish-FfmpegExecutable $root $source 'ffmpeg' $size $sha}}
 foreach($tool in @($null,'FFMPEG','../ffmpeg',1)){MustFail {Publish-FfmpegExecutable $root $source $tool ([long]3) $sha}}
 MustFail {Publish-FfmpegExecutable '.' $source 'ffmpeg' ([long]3) $sha}
 $cancel=[Threading.CancellationTokenSource]::new();try{$cancel.Cancel();$wasCanceled=$false;try{$null=Publish-FfmpegExecutable $root $source 'ffmpeg' ([long]3) $sha -CancellationToken $cancel.Token}catch{if($_.Exception.GetBaseException() -is [OperationCanceledException]){$wasCanceled=$true}else{throw}};Assert $wasCanceled 'Cancelamento externo tipado'}finally{$cancel.Dispose()}
 $script:publishCopyOriginal=${function:Copy-CheckedFfmpegArchiveStream}
 $script:publishLateCancel=[Threading.CancellationTokenSource]::new()
 function Copy-CheckedFfmpegArchiveStream {
  [CmdletBinding()]
  param([IO.Stream]$Source,[IO.Stream]$Destination,[object]$ExpectedSize,[object]$ExpectedSha256,[int]$TimeoutSeconds=120,[Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
  Assert ($TimeoutSeconds -eq 2 -and $CancellationToken.Equals($script:publishLateCancel.Token)) 'Timeout e token repassados'
  $receipt=& $script:publishCopyOriginal @PSBoundParameters
  $script:publishLateCancel.Cancel()
  return $receipt
 }
 try{
  $lateCanceled=$false
  try{$null=Publish-FfmpegExecutable $root $source 'ffmpeg' ([long]3) $sha -TimeoutSeconds 2 -CancellationToken $script:publishLateCancel.Token}catch{if($_.Exception.GetBaseException() -is [OperationCanceledException]){$lateCanceled=$true}else{throw}}
  Assert $lateCanceled 'Cancelamento durante copia impede Move'
  Assert (![IO.File]::Exists($ffmpeg) -and @([IO.Directory]::EnumerateFiles($root,'.ffmpeg.publish.*.tmp')).Count -eq 0 -and $source.CanRead -and $source.Position -eq 2) 'Cancelamento tardio limpa temp e preserva caller'
 }finally{$script:publishLateCancel.Dispose()}
 Assert (@([IO.Directory]::EnumerateFiles($root)).Count -eq 2 -and [IO.File]::ReadAllText($sentinel) -ceq 'preservar' -and $source.Position -eq 2 -and $source.CanRead) 'Falhas semresiduos/sentinela/caller'
}finally{
 $source.Dispose()
 foreach($name in @('ffmpeg.exe','ffprobe.exe','keep.txt','source[1].exe')){$p=Join-Path $root $name;if([IO.File]::Exists($p)){[IO.File]::Delete($p)}}
 [IO.Directory]::Delete($root,$false)
}
Write-Output "FFMPEG_PUBLISH_CANCELLATION_PASS checks=$checks; fixture abc, sem binario real/execucao"
