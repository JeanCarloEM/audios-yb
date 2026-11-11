#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'diretorio_zip_ffmpeg.ps1')
$checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:checks++}
# APPNOTE: prefixo30, cabecalho central46 em30, EOCD22 em76, localoffset0.
[byte[]]$end=0x50,0x4b,0x05,0x06,0,0,0,0,1,0,1,0,46,0,0,0,30,0,0,0,0,0
$fixture=[byte[]]::new(98);[Array]::Copy([byte[]](0x50,0x4b,1,2),0,$fixture,30,4);[Array]::Copy($end,0,$fixture,76,22)
function Invoke-Case([byte[]]$data,[bool]$valid){
 $stream=[IO.MemoryStream]::new($data)
 try{
  $stream.Position=5;$failed=$false;$result=$null
  try{$result=Get-FfmpegZipDirectory $stream}catch{$failed=$true}
  Assert ($failed -ne $valid) 'Aceite/rejeicao divergente'
  if($valid){Assert ($result -is [hashtable] -and $result.Count -eq 3 -and $result.entry_count -eq 1 -and $result.directory_offset -eq 30 -and $result.directory_size -eq 46) 'Descritor errado'}
  Assert ($stream.Position -eq 5 -and $stream.CanRead) 'Ownership/posicao'
 }finally{$stream.Dispose()}
}
Invoke-Case $fixture $true
foreach($mutation in @(@(30,[byte[]](0)),@(64,[byte[]](1,0)),@(72,[byte[]](30,0,0,0)),@(58,[byte[]](1,0)),@(84,[byte[]](2,0,2,0)))){
 $copy=[byte[]]$fixture.Clone();[Array]::Copy($mutation[1],0,$copy,$mutation[0],$mutation[1].Length)
 Invoke-Case $copy $false
}
$real=[IO.MemoryStream]::new()
try{
 $zip=[IO.Compression.ZipArchive]::new($real,[IO.Compression.ZipArchiveMode]::Create,$true)
 try{$null=$zip.CreateEntry('x.txt');$null=$zip.CreateEntry('dir/y.txt')}finally{$zip.Dispose()}
 $real.Position=3;$result=Get-FfmpegZipDirectory $real
 Assert ($result.entry_count -eq 2 -and $result.directory_offset -gt 0 -and $result.directory_size -gt 92) 'ZIP .NET multiplas entradas'
 Assert ($real.Position -eq 3 -and $real.CanRead) 'Ownership .NET'
}finally{$real.Dispose()}

Add-Type -TypeDefinition @'
using System;
using System.IO;
public sealed class FfmpegCentralPartialStream:MemoryStream {
 public int CentralReads; public bool FailCentral; private bool central;
 public FfmpegCentralPartialStream(byte[] data):base(data){}
 public override long Position {get{return base.Position;}set{base.Position=value;central=value==30;}}
 public override int Read(byte[] b,int o,int n){if(central){CentralReads++;if(FailCentral)return 0;}return base.Read(b,o,Math.Min(n,3));}
}
'@
$partial=[FfmpegCentralPartialStream]::new($fixture)
try{
 $partial.Position=5;$r=Get-FfmpegZipDirectory $partial
 if($r.entry_count -ne 1 -or $r.directory_offset -ne 30 -or $r.directory_size -ne 46){throw 'Descritor partial divergente'}
 if($partial.CentralReads -ne 16 -or $partial.Position -ne 5 -or !$partial.CanRead){throw 'Partial nao exercitado/ownership'}
 $partial.FailCentral=$true;$failed=$false
 try{$null=Get-FfmpegZipDirectory $partial}catch{$failed=$true}
 if(!$failed -or $partial.Position -ne 5 -or !$partial.CanRead){throw 'Zero read/ownership nao respeitado'}
}finally{$partial.Dispose()}
Write-Output 'ZIP_CENTRAL_PASS checks=18; delimitacao somente, sem extracao/CRC/nomes'
