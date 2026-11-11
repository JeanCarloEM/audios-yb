#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'validacao_transferencia_ffmpeg.ps1')
$script:Checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:Checks++}
$uri='https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/autobuild-2026-11-10-12-39/ffmpeg-n9.0.2-48-gd4070a14ce-win64-lgpl-9.0.zip'
$sha='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
$dest=[IO.MemoryStream]::new()
try{
 foreach($u in @($uri,([uri]$uri),$uri.Replace('win64','winarm64'))){
  $r=Test-FfmpegArchiveTransfer -Uri $u -Destination $dest -ExpectedSize ([long]3) -ExpectedSha256 $sha
  Assert ($r -is [bool] -and $r) 'Aceitar somente contrato de parametros; nao comprova bytesZIP'
 }
 foreach($u in @($null,123,'relative','https://api.github.com/repos/FFmpeg-Builds/FFmpeg-Builds/releases?per_page=3','https://release-assets.githubusercontent.com/x',$uri.Replace('ffmpeg-n9.0.2-48-gd4070a14ce-win64-lgpl-9.0.zip','checksums.sha256'),$uri.Replace('https:','http:'),$uri.Replace('github.com','evil.test'),$uri.Replace('lgpl-9.0.zip','gpl-9.0.zip'),$uri.Replace('2026-11-10','2026-02-30'),($uri+'?x=1'))){
  $r=Test-FfmpegArchiveTransfer -Uri $u -Destination $dest -ExpectedSize ([long]3) -ExpectedSha256 $sha
  Assert ($r -is [bool] -and !$r) 'URL invalida recusada sem excecao'
 }
 foreach($size in @($null,3,'3',([long]0),([long]536870913))){
  $r=Test-FfmpegArchiveTransfer -Uri $uri -Destination $dest -ExpectedSize $size -ExpectedSha256 $sha
  Assert ($r -is [bool] -and !$r) 'Size exige long1..512MiB'
 }
 foreach($hash in @($null,123,$sha.ToUpperInvariant(),$sha.Substring(1))){
  $r=Test-FfmpegArchiveTransfer -Uri $uri -Destination $dest -ExpectedSize ([long]3) -ExpectedSha256 $hash
  Assert ($r -is [bool] -and !$r) 'SHA exige stringASCII64lower'
 }
 $readOnly=[IO.MemoryStream]::new([byte[]]@(1),$false)
 $closed=[IO.MemoryStream]::new();$closed.Dispose()
 try{foreach($d in @($null,123,$readOnly,$closed)){$r=Test-FfmpegArchiveTransfer -Uri $uri -Destination $d -ExpectedSize ([long]3) -ExpectedSha256 $sha;Assert ($r -is [bool] -and !$r) 'Destino precisa ser stream gravavel'}}finally{$readOnly.Dispose()}
 Assert ($dest.CanWrite -and $dest.Length -eq 0) 'Validacao nao escreve nem fecha destino'
}finally{$dest.Dispose()}
"FFMPEG_ARCHIVE_TRANSFER_VALIDATION_PASS checks$script:Checks; sem HTTP/copia/arquivos"
