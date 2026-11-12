#requires -Version 7.0
. (Join-Path $PSScriptRoot 'leitura_candidato_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'versao_ffmpeg.ps1')
function Invoke-WithVerifiedFfmpegCandidate {
 [CmdletBinding()]
 param(
  [AllowNull()][object]$Path,
  [AllowNull()][object]$ExpectedSize,
  [AllowNull()][object]$ExpectedSha256,
  [AllowNull()][object]$Tool,
  [AllowNull()][object]$ExpectedBuildVersion,
  [AllowNull()][object]$Invoker,
  [AllowNull()][object]$Action
 )
 if($Invoker -isnot [scriptblock] -or $Action -isnot [scriptblock]){throw 'Invoker e Action devem ser scriptblocks.'}
 if($Tool -isnot [string] -or ($Tool -cne 'ffmpeg' -and $Tool -cne 'ffprobe')){throw 'Tool invalido.'}
 if($ExpectedBuildVersion -isnot [string] -or $ExpectedBuildVersion.Length -gt 160 -or $ExpectedBuildVersion -cnotmatch '\An[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9]+-g[0-9a-f]{7,40})?\z'){throw 'ExpectedBuildVersion invalido.'}
 $verifiedCandidateTool=$Tool;$verifiedCandidateBuild=$ExpectedBuildVersion
 $verifiedCandidateInvoker=$Invoker;$verifiedCandidateConsumer=$Action
 Invoke-WithFfmpegCandidateReadLock -Path $Path -ExpectedSize $ExpectedSize -ExpectedSha256 $ExpectedSha256 -Action {
  param($verificationReadStream,$verificationLockedPath)
  $fixedVersionArguments=[string[]]@('-version')
  $verificationReply=& $verifiedCandidateInvoker $verificationLockedPath $fixedVersionArguments 15
  if($verificationReply -isnot [hashtable] -or $verificationReply.code -isnot [int] -or $verificationReply.code -ne 0 -or $verificationReply.timeout -isnot [bool] -or $verificationReply.timeout -or $verificationReply.out -isnot [string] -or $verificationReply.err -isnot [string] -or $verificationReply.err.Length -gt 65536){throw 'Invocacao -version falhou ou retornou contrato invalido.'}
  $verificationMetadata=Read-FfmpegVersionHeader -Output $verificationReply.out -Tool $verifiedCandidateTool -ExpectedBuildVersion $verifiedCandidateBuild
  & $verifiedCandidateConsumer $verificationMetadata $verificationLockedPath $verificationReadStream
 }
}