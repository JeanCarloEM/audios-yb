#requires -Version 7.0
. (Join-Path $PSScriptRoot 'metadados_alvos_zip_ffmpeg.ps1')
function Invoke-WithFfmpegZipEntryStream {
 [CmdletBinding()]
 param(
  [AllowNull()][object]$ArchiveStream,
  [AllowNull()][object]$ExpectedRootDirectory,
  [AllowNull()][object]$Tool,
  [AllowNull()][object]$Action,
  [Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None
 )
 if($ArchiveStream -isnot [IO.Stream] -or !$ArchiveStream.CanRead -or !$ArchiveStream.CanSeek){throw 'ArchiveStream deve ser legivel e permitir busca.'}
 if($Tool -isnot [string] -or ($Tool -cne 'ffmpeg' -and $Tool -cne 'ffprobe')){throw 'Tool deve ser ffmpeg ou ffprobe.'}
 if($Action -isnot [scriptblock]){throw 'Action deve ser scriptblock.'}
 $entryHandle=$null;$ownedZip=$null;$entryOriginalPosition=$ArchiveStream.Position
 try{
  $CancellationToken.ThrowIfCancellationRequested()
  $entryMetadata=(Read-FfmpegZipTargetMetadata -Stream $ArchiveStream -ExpectedRootDirectory $ExpectedRootDirectory)[$Tool]
  $ArchiveStream.Position=0
  $ownedZip=[IO.Compression.ZipArchive]::new($ArchiveStream,[IO.Compression.ZipArchiveMode]::Read,$true)
  $selectedEntry=$ownedZip.GetEntry($entryMetadata.path)
  if($null -eq $selectedEntry -or $selectedEntry.Length -ne $entryMetadata.size -or $selectedEntry.CompressedLength -ne $entryMetadata.compressed_size){throw 'Entrada diverge dos metadados validados.'}
  $CancellationToken.ThrowIfCancellationRequested()
  $entryHandle=$selectedEntry.Open()
  & $Action $entryHandle $entryMetadata
 }finally{
  try{if($null -ne $entryHandle){$entryHandle.Dispose()}}
  finally{
   try{if($null -ne $ownedZip){$ownedZip.Dispose()}}
   finally{$ArchiveStream.Position=$entryOriginalPosition}
  }
 }
}