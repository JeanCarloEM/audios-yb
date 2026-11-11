#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'rodape_zip_ffmpeg.ps1')
$checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:checks++}
# Fixture independente: EOCD PKWARE em46; diretorio declarado46,offset0,count1/1.
[byte[]]$end=0x50,0x4b,0x05,0x06,0,0,0,0,1,0,1,0,46,0,0,0,0,0,0,0,0,0
$bytes=[byte[]]::new(68);[Array]::Copy($end,0,$bytes,46,22)
$ms=[IO.MemoryStream]::new($bytes)
try{
 $ms.Position=3;$r=Get-FfmpegZipEndRecord $ms
 Assert ($r -is [hashtable] -and $r.Count -eq 3) 'map3'
 Assert ($r.entry_count -is [int] -and $r.entry_count -eq 1 -and $r.directory_offset -is [long] -and $r.directory_offset -eq 0 -and $r.directory_size -is [long] -and $r.directory_size -eq 46) 'Campos/tipos'
 Assert ($ms.Position -eq 3 -and $ms.CanRead) 'Propriedade/posicao sucesso'
 $bytes[56]=2;$ms.Position=0;$ms.Write($bytes,0,68);$ms.Position=5
 $failed=$false;try{$null=Get-FfmpegZipEndRecord $ms}catch{$failed=$true}
 Assert $failed 'Contagens divergentes aceitas'
 Assert ($ms.Position -eq 5 -and $ms.CanRead) 'Propriedade/posicao erro'
}finally{$ms.Dispose()}
# Fonte independente adicional: arquivo ZIP gerado pelo runtime, sem extracao.
$real=[IO.MemoryStream]::new()
try{
 $zip=[IO.Compression.ZipArchive]::new($real,[IO.Compression.ZipArchiveMode]::Create,$true)
 try{$null=$zip.CreateEntry('x.txt')}finally{$zip.Dispose()}
 $real.Position=2;$r=Get-FfmpegZipEndRecord $real
 Assert ($r.entry_count -eq 1 -and $r.directory_size -ge 46 -and $r.directory_offset -gt 0) 'ZIP .NET'
 Assert ($real.Position -eq 2 -and $real.CanRead) 'Propriedade ZIP .NET'
}finally{$real.Dispose()}
# Campos independentes APPNOTE: offset dentro do EOCD e bytes little-endian invalidos.
$negativeCases=@(
 @('disco',4,[byte[]](1,0)), @('disco-diretorio',6,[byte[]](1,0)),
 @('contagem-zero',8,[byte[]](0,0,0,0)), @('contagem4097',8,[byte[]](1,16,1,16)),
 @('contagem-ZIP64',8,[byte[]](255,255,255,255)), @('diretorio45',12,[byte[]](45,0,0,0)),
 @('diretorio8388609',12,[byte[]](1,0,128,0)), @('offset-incoerente',16,[byte[]](1,0,0,0)),
 @('tamanho-ZIP64',12,[byte[]](255,255,255,255)), @('offset-ZIP64',16,[byte[]](255,255,255,255)),
 @('assinatura',0,[byte[]](0,0,0,0)), @('comentario-truncado',20,[byte[]](1,0))
)
foreach($case in $negativeCases){
 $fixture=[byte[]]::new(68);[Array]::Copy($end,0,$fixture,46,22)
 [Array]::Copy($case[2],0,$fixture,(46+$case[1]),$case[2].Length)
 $inputStream=[IO.MemoryStream]::new($fixture)
 try{
  $inputStream.Position=7;$rejected=$false
  try{$null=Get-FfmpegZipEndRecord $inputStream}catch{$rejected=$true}
  Assert $rejected ('Caso invalido aceito: '+$case[0])
  Assert ($inputStream.Position -eq 7 -and $inputStream.CanRead) ('Ownership/posicao: '+$case[0])
 }finally{$inputStream.Dispose()}
}
foreach($invalidInput in @($null,'texto')){
 $rejected=$false;try{$null=Get-FfmpegZipEndRecord $invalidInput}catch{$rejected=$true}
 Assert $rejected 'Argumento invalido aceito'
}
$shortStream=[IO.MemoryStream]::new([byte[]]::new(21))
try{
 $shortStream.Position=4;$rejected=$false
 try{$null=Get-FfmpegZipEndRecord $shortStream}catch{$rejected=$true}
 Assert $rejected 'Length21 aceito'
 Assert ($shortStream.Position -eq 4 -and $shortStream.CanRead) 'Ownership/posicao length21'
}finally{$shortStream.Dispose()}
Write-Output "ZIP_END_MEMORY_PASS checks=$checks; cobertura complementar pendente"
