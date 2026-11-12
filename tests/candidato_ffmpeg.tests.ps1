#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'candidato_ffmpeg.ps1')
$checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Operacao invalida aceita'}
$fixtureRoot=Join-Path (Split-Path -Parent $PSScriptRoot) ('.runtime-candidate-['+[guid]::NewGuid().ToString('N')+']')
[void][IO.Directory]::CreateDirectory($fixtureRoot)
$sentinel=Join-Path $fixtureRoot 'ffmpeg.exe';[IO.File]::WriteAllText($sentinel,'preservar')
$script:observedPath=$null;$script:observedStream=$null;$script:called=0
try{
 foreach($tool in @('ffmpeg','ffprobe')){
  $result=Invoke-WithFfmpegCandidateFile -RootDirectory $fixtureRoot -Tool $tool -Action {
   param($path,$stream)
   $script:observedPath=$path;$script:observedStream=$stream;$script:called++
   Assert ([IO.File]::Exists($path) -and $stream -is [IO.FileStream] -and $stream.CanWrite -and $stream.Length -eq 0) 'Novo arquivo owned'
   Assert ([IO.Path]::GetDirectoryName($path) -ceq $fixtureRoot -and [IO.Path]::GetFileName($path) -cmatch ('\A\.ffmpeg\.candidate\.[0-9a-f]{32}\.'+$tool+'\.exe\z')) 'Nome/raiz literal'
   $stream.WriteByte(97);$stream.Flush()
   MustFail {$extra=[IO.File]::OpenRead($path);$extra.Dispose()}
   'candidate-ok'
  }
  Assert ($result -ceq 'candidate-ok' -and ![IO.File]::Exists($script:observedPath)) 'Saida/cleanup sucesso'
  Assert (!$script:observedStream.CanWrite -and [IO.File]::ReadAllText($sentinel) -ceq 'preservar') 'Fechado/sentinela'
 }
 MustFail {Invoke-WithFfmpegCandidateFile $fixtureRoot 'ffmpeg' {param($path,$stream)$script:observedPath=$path;$script:observedStream=$stream;$stream.WriteByte(97);throw 'consumer-error'}}
 Assert (![IO.File]::Exists($script:observedPath) -and !$script:observedStream.CanWrite) 'Cleanup erro'
 foreach($badTool in @($null,'FFMPEG','../ffmpeg',1)){MustFail {Invoke-WithFfmpegCandidateFile $fixtureRoot $badTool {$script:called++}}}
 foreach($badRoot in @($null,'.',$sentinel)){MustFail {Invoke-WithFfmpegCandidateFile $badRoot 'ffmpeg' {$script:called++}}}
 MustFail {Invoke-WithFfmpegCandidateFile $fixtureRoot 'ffmpeg' $null}
 Assert ($script:called -eq 2 -and @([IO.Directory]::EnumerateFiles($fixtureRoot)).Count -eq 1 -and [IO.File]::ReadAllText($sentinel) -ceq 'preservar') 'Invalidos antes criacao/sentinela'
}finally{
 [IO.File]::Delete($sentinel)
 [IO.Directory]::Delete($fixtureRoot,$false)
}
Write-Output "FFMPEG_CANDIDATE_FILE_PASS checks=$checks; fixture propria, sem ZIP/execucao/publicacao"
