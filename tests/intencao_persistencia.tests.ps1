#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1.0
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'publicacao_pendente.ps1')
# Fixture de QUATRO BYTES, nao audio admissivel. Persistir dados nao certifica qualidade.
$work=Join-Path $PSScriptRoot ('.runtime-intencao-persistencia-'+[guid]::NewGuid().ToString('N'))
$out=Join-Path $work 'out'
$control=Join-Path $out '.controle'
$fontes=Join-Path $control 'fontes'
$null=New-Item -ItemType Directory -Path $fontes
$ready=Join-Path $fontes 'source [literal].mp3'
$outside=Join-Path $out 'outside.mp3'
$bytes=[byte[]]@(0,1,2,255)
[IO.File]::WriteAllBytes($ready,$bytes)
[IO.File]::WriteAllBytes($outside,$bytes)
$sha=[Security.Cryptography.SHA256]::Create()
try{
 $audioHash=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
 $keyText=[string]::Join([char]31,@('1','AC/DC','iTunes DJ','https://www.youtube.com/watch?v=TestVideo01'))
 $key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($keyText))).Replace('-','').ToLowerInvariant()
 $filename=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes('TestVideo01'))).Replace('-','').ToLowerInvariant()+'.json'
}finally{$sha.Dispose()}
$note='Colet'+[char]0x00E2+'nea'
$record=@{chave=$key;ordem='1';artista='AC/DC';musica='iTunes DJ';url_original='https://www.youtube.com/watch?v=TestVideo01';video_id='TestVideo01';aprovacao_musical=@{fixture=$true};nota=$note}
$audit=@{validado=$true;politica='fixture-v1';origem_sha256=('a'*64);resultado_sha256=$audioHash}
$snapshot=New-PublicationIntentSnapshot -Ready $ready -Target (Join-Path $out 'final.mp3') -Control $control -Out $out -VideoId 'TestVideo01' -Record $record -Audit $audit -Probe @{fixture=$true}
$result=Save-PublicationIntentFile -Snapshot $snapshot -Control $control -Out $out
$expectedPath=Join-Path (Join-Path $control 'publicacoes_pendentes') $filename
if(-not [string]::Equals($result.Path,$expectedPath,[StringComparison]::Ordinal) -or $result.Status -cne 'persistida_nao_autorizada'){throw 'Destino/status da persistencia incorreto'}
$raw=[IO.File]::ReadAllBytes($expectedPath)
if($raw.Length -ge 3 -and $raw[0] -eq 239 -and $raw[1] -eq 187 -and $raw[2] -eq 191){throw 'BOM inesperado'}
$sha=[Security.Cryptography.SHA256]::Create()
try{$jsonHash=[BitConverter]::ToString($sha.ComputeHash($raw)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
if($result.Sha256 -cne $jsonHash){throw 'Hash do JSON incorreto'}
$stored=ConvertFrom-Json -AsHashtable ([IO.File]::ReadAllText($expectedPath))
if($stored.schema -cne 'audios-yb-publication-intent/v1' -or $stored.status -cne 'preparada' -or $stored.sha256 -cne $audioHash -or $stored.tamanho -ne 4 -or $stored.video_id -cne 'TestVideo01' -or $stored.registro.chave -cne $key -or -not [string]::Equals($stored.registro.nota,$note,[StringComparison]::Ordinal)){throw 'Dados persistidos divergentes'}
if($snapshot.status -cne 'preparada_nao_persistida' -or $snapshot.ContainsKey('persistido_utc')){throw 'Snapshot de entrada alterado'}
# Ler o texto JSON preserva o fuso; ConvertFrom-Json pode converter ISO em DateTime.
$document=[Text.Json.JsonDocument]::Parse([IO.File]::ReadAllText($expectedPath))
try{$storedUtc=$document.RootElement.GetProperty('persistido_utc').GetString()}finally{$document.Dispose()}
if(-not $storedUtc.EndsWith('Z',[StringComparison]::Ordinal) -or [DateTimeOffset]::Parse($storedUtc,[Globalization.CultureInfo]::InvariantCulture).Offset -ne [TimeSpan]::Zero){throw 'Timestamp persistido nao UTC'}
$cases=@(
 @{Name='existente';Data=$snapshot;Type=[IO.IOException];Message='existente'},
 @{Name='hash';Data=$snapshot.Clone();Type=[IO.InvalidDataException];Message='Hash'},
 @{Name='fora';Data=$snapshot.Clone();Type=[ArgumentException];Message='Control'},
 @{Name='id';Data=$snapshot.Clone();Type=[IO.InvalidDataException];Message='video_id'},
 @{Name='utc';Data=$snapshot.Clone();Type=[ArgumentException];Message='UTC'},
 @{Name='schema';Data=$snapshot.Clone();Type=[ArgumentException];Message='Schema'}
)
$cases[1].Data.sha256=('0'*64)
$cases[2].Data.pronto_relativo='../outside.mp3'
$cases[3].Data.video_id='testVideo01'
$cases[4].Data.criado_utc='2026-11-06T12:00:00+01:00'
$cases[5].Data.schema=$snapshot.schema+[char]0x00AD
foreach($case in $cases){
 $caught=$false
 try{$null=Save-PublicationIntentFile -Snapshot $case.Data -Control $control -Out $out}
 catch{
  if(-not $case.Type.IsInstanceOfType($_.Exception) -or $_.Exception.Message.IndexOf($case.Message,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw}
  $caught=$true
 }
 if(-not $caught){throw ('Controle negativo aceito: '+$case.Name)}
}
if($IsWindows){
 # Juncoes requerem volume com suporte; o workspace pode estar em exFAT.
 $linkParent=$work
 $workspaceDrive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($work))
 if(-not [string]::Equals($workspaceDrive.DriveFormat,'NTFS',[StringComparison]::OrdinalIgnoreCase)){
  $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
  $tempDrive=[IO.DriveInfo]::new([IO.Path]::GetPathRoot($tempRoot))
  if(-not [string]::Equals($tempDrive.DriveFormat,'NTFS',[StringComparison]::OrdinalIgnoreCase)){throw 'Teste de juncao requer temporario NTFS'}
  $linkParent=[IO.Path]::GetFullPath([IO.Path]::Combine($tempRoot,('audios-yb-junction-'+[guid]::NewGuid().ToString('N'))))
  if(-not [string]::Equals([IO.Path]::GetDirectoryName($linkParent),[IO.Path]::TrimEndingDirectorySeparator($tempRoot),[StringComparison]::OrdinalIgnoreCase)){throw 'Temporario de juncao fora do escopo'}
  $null=[IO.Directory]::CreateDirectory($linkParent)
 }
 $link=Join-Path $linkParent 'out-link'
 $null=New-Item -ItemType Junction -Path $link -Target $out
 $caught=$false
 try{$null=Save-PublicationIntentFile -Snapshot $snapshot -Control (Join-Path $link '.controle') -Out $link}
 catch [NotSupportedException]{$caught=$true}
 if(-not $caught){throw 'Juncao nao foi recusada'}
}else{Write-Output 'INTENCAO_JUNCAO_NAO_TESTADA_NESTE_SO'}
$directory=Join-Path $control 'publicacoes_pendentes'
if(@(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File).Count -ne 1 -or @(Get-ChildItem -LiteralPath $directory -Filter '*.tmp' -File -Force).Count -ne 0){throw 'Colisao produziu arquivos adicionais ou temporarios'}
if((Get-FileHash -LiteralPath $expectedPath).Hash.ToLowerInvariant() -cne $jsonHash -or (Get-FileHash -LiteralPath $ready).Hash.ToLowerInvariant() -cne $audioHash -or (Get-FileHash -LiteralPath $outside).Hash.ToLowerInvariant() -cne $audioHash -or (Test-Path -LiteralPath (Join-Path $out 'final.mp3'))){throw 'Dados sobrescritos ou audio publicado'}
Write-Output 'INTENCAO_PERSISTENCIA_PASS'
