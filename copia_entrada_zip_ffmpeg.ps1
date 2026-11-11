#requires -Version 7.0
. (Join-Path $PSScriptRoot 'entrada_zip_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'copia_executavel_ffmpeg.ps1')
function Copy-FfmpegZipExecutable {
 [CmdletBinding()]
 param(
  [AllowNull()][object]$ArchiveStream,
  [AllowNull()][object]$ExpectedRootDirectory,
  [AllowNull()][object]$Tool,
  [AllowNull()][object]$DestinationStream,
  [ValidateRange(1,300)][int]$TimeoutSeconds=120,
  [Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None
 )
 if($DestinationStream -isnot [IO.Stream] -or !$DestinationStream.CanWrite){throw 'DestinationStream deve ser gravavel.'}
 if([object]::ReferenceEquals($ArchiveStream,$DestinationStream)){throw 'ArchiveStream e DestinationStream devem ser distintos.'}
 $zipCopyDest=$DestinationStream;$zipCopyToolName=$Tool;$zipCopySeconds=$TimeoutSeconds;$zipCopyToken=$CancellationToken
 Invoke-WithFfmpegZipEntryStream -ArchiveStream $ArchiveStream -ExpectedRootDirectory $ExpectedRootDirectory -Tool $Tool -CancellationToken $CancellationToken -Action {
  param($zipCopyEntry,$zipCopyMetadata)
  $zipCopyReceipt=Copy-FfmpegExecutableStream -SourceStream $zipCopyEntry -DestinationStream $zipCopyDest -ExpectedSize $zipCopyMetadata.size -TimeoutSeconds $zipCopySeconds -CancellationToken $zipCopyToken
  @{tool=$zipCopyToolName;entry_path=$zipCopyMetadata.path;size=$zipCopyReceipt.size;sha256=$zipCopyReceipt.sha256}
 }
}