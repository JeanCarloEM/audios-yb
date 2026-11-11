#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'metadados_alvos_zip_ffmpeg.ps1')
$checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:checks++}
function New-Fixture([string[]]$paths,[int]$attributes=32){
 $memory=[IO.MemoryStream]::new()
 $archive=[IO.Compression.ZipArchive]::new($memory,[IO.Compression.ZipArchiveMode]::Create,$true)
 try{foreach($path in $paths){$entry=$archive.CreateEntry($path);$entry.ExternalAttributes=$attributes;$s=$entry.Open();try{$s.WriteByte(97)}finally{$s.Dispose()}}}finally{$archive.Dispose()}
 return ,$memory
}
$paths=@('ffmpeg-fixture/bin/ffmpeg.exe','ffmpeg-fixture/bin/ffprobe.exe')
$stream=New-Fixture $paths
try{
 $stream.Position=4;$r=Read-FfmpegZipTargetMetadata -Stream $stream -ExpectedRootDirectory 'ffmpeg-fixture'
 Assert ($r -is [hashtable] -and $r.Count -eq 2) 'Map2'
 foreach($key in @('ffmpeg','ffprobe')){Assert ($r[$key] -is [hashtable] -and $r[$key].Count -eq 3 -and $r[$key].path -ceq ('ffmpeg-fixture/bin/'+$key+'.exe') -and $r[$key].size -is [long] -and $r[$key].size -eq 1 -and $r[$key].compressed_size -is [long] -and $r[$key].compressed_size -gt 0) 'Contrato metadados'}
 Assert ($stream.Position -eq 4 -and $stream.CanRead) 'Ownership/Position'
}finally{$stream.Dispose()}
$cases=@(
 @(@($paths[0]),32), @(@($paths[0],$paths[1],$paths[0]),32),
 @(@('ffmpeg-fixture/../bin/ffmpeg.exe',$paths[1]),32),
 @(@('ffmpeg-fixture/bin/FFMPEG.EXE',$paths[1]),32),
 @($paths,-1610612736), @($paths,16), @($paths,1024)
)
foreach($case in $cases){
 $stream=New-Fixture $case[0] $case[1]
 try{
  $stream.Position=3;$failed=$false;try{$null=Read-FfmpegZipTargetMetadata $stream 'ffmpeg-fixture'}catch{$failed=$true}
  Assert $failed 'Alvos inseguros/incompletos aceitos'
  Assert ($stream.Position -eq 3 -and $stream.CanRead) 'Ownership erro'
 }finally{$stream.Dispose()}
}
$stream=New-Fixture $paths
try{
 foreach($root in @('../ffmpeg-fixture','ffmpeg-fixture/bin',"ffmpeg-fixture`n")){
  $failed=$false;try{$null=Read-FfmpegZipTargetMetadata $stream $root}catch{$failed=$true};Assert $failed 'Raiz invalida aceita'
 }
}finally{$stream.Dispose()}

# Contraprova independente: caminhos do ZIP combinam com raiz insegura fornecida.
foreach($badRoot in @('../ffmpeg-fixture','ffmpeg-fixture/bin',"ffmpeg-fixture`n")){
 [string[]]$badPaths=@(($badRoot+'/bin/ffmpeg.exe'),($badRoot+'/bin/ffprobe.exe'))
 if($badPaths.Count -ne 2){throw 'Fixture incorreta'}
 $stream=New-Fixture $badPaths
 try{
  $stream.Position=4;$failed=$false
  try{$null=Read-FfmpegZipTargetMetadata $stream $badRoot}catch{$failed=$true}
  if(!$failed){throw 'Raiz insegura correspondente aceita'}
  if($stream.Position -ne 4 -or !$stream.CanRead){throw 'Ownership/Position raiz'}
 }finally{$stream.Dispose()}
}
Write-Output 'ZIP_TARGET_METADATA_PASS checks=27; sem extracao/execucao'
