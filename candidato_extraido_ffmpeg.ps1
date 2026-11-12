#requires -Version 7.0
. (Join-Path $PSScriptRoot 'candidato_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'copia_entrada_zip_ffmpeg.ps1')
function Invoke-WithExtractedFfmpegCandidate {
 [CmdletBinding()]
 param(
  [AllowNull()][object]$RootDirectory,
  [AllowNull()][object]$ArchiveStream,
  [AllowNull()][object]$ExpectedRootDirectory,
  [AllowNull()][object]$Tool,
  [AllowNull()][object]$Action,
  [ValidateRange(1,300)][int]$TimeoutSeconds=120,
  [Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None
 )
 if($Action -isnot [scriptblock]){throw 'Action deve ser scriptblock.'}
 if($ArchiveStream -isnot [IO.Stream] -or !$ArchiveStream.CanRead -or !$ArchiveStream.CanSeek){throw 'ArchiveStream deve ser legivel e permitir busca.'}
 $CancellationToken.ThrowIfCancellationRequested()
 $extractArchive=$ArchiveStream;$extractRoot=$ExpectedRootDirectory;$extractTool=$Tool
 $extractConsumer=$Action;$extractSeconds=$TimeoutSeconds;$extractToken=$CancellationToken
 Invoke-WithFfmpegCandidateFile -RootDirectory $RootDirectory -Tool $Tool -Action {
  param($extractedPath,$extractedWriteStream)
  $extractReceipt=Copy-FfmpegZipExecutable -ArchiveStream $extractArchive -ExpectedRootDirectory $extractRoot -Tool $extractTool -DestinationStream $extractedWriteStream -TimeoutSeconds $extractSeconds -CancellationToken $extractToken
  $extractedWriteStream.Flush()
  if($extractedWriteStream.Length -ne $extractReceipt.size){throw 'Tamanho do candidato diverge do recibo.'}
  $extractedWriteStream.Dispose()
  $extractToken.ThrowIfCancellationRequested()
  & $extractConsumer $extractedPath $extractReceipt
 }
}