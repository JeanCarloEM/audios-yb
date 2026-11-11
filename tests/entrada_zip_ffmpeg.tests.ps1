#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'entrada_zip_ffmpeg.ps1')
$checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Operacao invalida aceita'}
$archive=[IO.MemoryStream]::new();$zip=[IO.Compression.ZipArchive]::new($archive,[IO.Compression.ZipArchiveMode]::Create,$true)
try{foreach($tool in @('ffmpeg','ffprobe')){$entry=$zip.CreateEntry('ffmpeg-fixture/bin/'+$tool+'.exe');$entry.ExternalAttributes=32;$s=$entry.Open();try{$s.WriteByte($(if($tool -ceq 'ffmpeg'){97}else{100}))}finally{$s.Dispose()}}}finally{$zip.Dispose()}
$script:savedEntry=$null;$script:callbackCount=0
try{
 foreach($tool in @('ffmpeg','ffprobe')){
  $archive.Position=4
  $result=Invoke-WithFfmpegZipEntryStream -ArchiveStream $archive -ExpectedRootDirectory 'ffmpeg-fixture' -Tool $tool -Action {
   param($entryStream,$metadata)
   $script:savedEntry=$entryStream;$script:callbackCount++
   Assert ($metadata -is [hashtable] -and $metadata.path -ceq ('ffmpeg-fixture/bin/'+$tool+'.exe') -and $metadata.size -eq 1) 'Metadata do alvo'
   Assert ($entryStream.ReadByte() -eq $(if($tool -ceq 'ffmpeg'){97}else{100})) 'Bytes do alvo'
   'consumer-ok'
  }
  Assert ($result -ceq 'consumer-ok' -and $archive.Position -eq 4 -and $archive.CanRead) 'Saida/ownership'
  $closed=$false;try{$null=$script:savedEntry.ReadByte()}catch{$closed=$true};Assert $closed 'Stream de entrada nao fechado'
 }
 $archive.Position=4
 MustFail {Invoke-WithFfmpegZipEntryStream $archive 'ffmpeg-fixture' 'ffmpeg' {param($s,$m)$script:savedEntry=$s;throw 'consumer-failure'}}
 $closed=$false;try{$null=$script:savedEntry.ReadByte()}catch{$closed=$true};Assert ($closed -and $archive.Position -eq 4 -and $archive.CanRead) 'Cleanup erro'
 foreach($badTool in @($null,'FFMPEG','other',1)){MustFail {Invoke-WithFfmpegZipEntryStream $archive 'ffmpeg-fixture' $badTool {$script:callbackCount++;throw 'Callback nao deveria executar'}}}
 MustFail {Invoke-WithFfmpegZipEntryStream $archive 'ffmpeg-fixture' 'ffmpeg' $null}
 Assert ($archive.Position -eq 4 -and $archive.CanRead) 'Ownership argumentos invalidos'
 $cts=[Threading.CancellationTokenSource]::new()
 try{$cts.Cancel();MustFail {Invoke-WithFfmpegZipEntryStream $archive 'ffmpeg-fixture' 'ffmpeg' {$script:callbackCount++} -CancellationToken $cts.Token};Assert ($script:callbackCount -eq 2 -and $archive.CanRead) 'Precancel callback'}finally{$cts.Dispose()}
}finally{$archive.Dispose()}
Write-Output "FFMPEG_OWNED_ENTRY_PASS checks=$checks; ZIP sintetico em memoria, sem filesystem/copia"
