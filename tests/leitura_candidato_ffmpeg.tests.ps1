#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'leitura_candidato_ffmpeg.ps1')
$checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Operacao invalida aceita'}
$root=Join-Path (Split-Path -Parent $PSScriptRoot) ('.runtime-read-lock-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$path=Join-Path $root 'candidate[1].exe';[IO.File]::WriteAllBytes($path,[byte[]](97,98,99))
$sha='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
$script:lockedStream=$null;$script:called=0
try{
 $result=Invoke-WithFfmpegCandidateReadLock -Path $path -ExpectedSize ([long]3) -ExpectedSha256 $sha -Action {
  param($readStream,$absolutePath)
  $script:lockedStream=$readStream;$script:called++
  Assert ($absolutePath -ceq $path -and $readStream.CanRead -and !$readStream.CanWrite -and $readStream.Position -eq 0 -and $readStream.Length -eq 3) 'Handle/root literal'
  Assert ($readStream.ReadByte() -eq 97) 'Rewind apos hash'
  MustFail {$w=[IO.File]::Open($path,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$w.Dispose()}
  MustFail {[IO.File]::Delete($path)}
  'read-locked-ok'
 }
 Assert ($result -ceq 'read-locked-ok' -and !$script:lockedStream.CanRead -and [IO.File]::ReadAllText($path) -ceq 'abc') 'Output/Dispose/bytes preservados'
 MustFail {Invoke-WithFfmpegCandidateReadLock $path ([long]3) $sha {param($s,$p)$script:lockedStream=$s;throw 'consumer-error'}}
 Assert (!$script:lockedStream.CanRead -and [IO.File]::Exists($path)) 'Dispose erro'
 foreach($size in @($null,3,'3',[long]0,[long]4,[long]536870913)){MustFail {Invoke-WithFfmpegCandidateReadLock $path $size $sha {$script:called++}}}
 foreach($badSha in @($null,'bad',$sha.ToUpperInvariant(),('0'*64))){MustFail {Invoke-WithFfmpegCandidateReadLock $path ([long]3) $badSha {$script:called++}}}
 MustFail {Invoke-WithFfmpegCandidateReadLock $path ([long]3) $sha $null}
 MustFail {Invoke-WithFfmpegCandidateReadLock $root ([long]3) $sha {$script:called++}}
 Assert ($script:called -eq 1 -and [IO.File]::ReadAllText($path) -ceq 'abc') 'Invalidos nao invocam consumidor'
}finally{[IO.File]::Delete($path);[IO.Directory]::Delete($root,$false)}
Write-Output "FFMPEG_CANDIDATE_READ_LOCK_PASS checks=$checks; fixture abc, sem executar/publicar"
