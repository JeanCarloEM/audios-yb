#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1.0
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'publicacao_pendente.ps1')
# Bytes abaixo NAO sao audio real. Testamos somente snapshot de dados/identidade/I/O por leitura.
$work=Join-Path $PSScriptRoot ('.runtime-intencao-'+[guid]::NewGuid().ToString('N'))
$out=Join-Path $work 'out'
$control=Join-Path $out '.controle'
$fontes=Join-Path $control 'fontes'
$sibling=Join-Path $out '.controleOutro'
$null=New-Item -ItemType Directory -Path $fontes,$sibling
$ready=Join-Path $fontes 'candidate [literal].mp3'
$outside=Join-Path $sibling 'candidate.mp3'
$existing=Join-Path $out 'existing.mp3'
$target=Join-Path $out 'final.mp3'
$bytes=[byte[]]@(0,1,2,255)
[IO.File]::WriteAllBytes($ready,$bytes)
[IO.File]::WriteAllBytes($outside,$bytes)
[IO.File]::WriteAllBytes($existing,[byte[]]@(9,8))
$sha=[Security.Cryptography.SHA256]::Create()
try{
 $expected=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
 $keyText=[string]::Join([char]31,@('1','AC/DC','iTunes DJ','https://www.youtube.com/watch?v=TestVideo01'))
 $key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($keyText))).Replace('-','').ToLowerInvariant()
}finally{$sha.Dispose()}
$existingHash=(Get-FileHash -LiteralPath $existing).Hash
$record=@{chave=$key;ordem='1';artista='AC/DC';musica='iTunes DJ';url_original='https://www.youtube.com/watch?v=TestVideo01';video_id='TestVideo01';aprovacao_musical=@{fixture=$true}}
$audit=@{validado=$true;politica='fixture-v1';origem_sha256=('a'*64);resultado_sha256=$expected;contexto=@{valor='original'}}
$probe=@{fixture=$true;detalhes=@{valor='original'}}
$base=@{Ready=$ready;Target=$target;Control=$control;Out=$out;VideoId='TestVideo01';Record=$record;Audit=$audit;Probe=$probe}
$snapshot=New-PublicationIntentSnapshot @base
if($snapshot -isnot [hashtable] -or $snapshot.schema -cne 'audios-yb-publication-intent/v1' -or $snapshot.status -cne 'preparada_nao_persistida'){throw 'Contrato de snapshot incorreto'}
if($snapshot.video_id -cne 'TestVideo01' -or $snapshot.arquivo -cne 'final.mp3' -or $snapshot.pronto_relativo -cne 'fontes/candidate [literal].mp3' -or $snapshot.tamanho -ne 4 -or $snapshot.sha256 -cne $expected){throw 'Dados de arquivo divergentes'}
if($snapshot.registro.ordem -cne '1' -or $snapshot.registro.artista -cne 'AC/DC' -or $snapshot.registro.musica -cne 'iTunes DJ' -or $snapshot.registro.chave -cne $key -or $snapshot.registro.url_original -cne 'https://www.youtube.com/watch?v=TestVideo01'){throw 'Dados canonicos divergentes'}
if($snapshot.ContainsKey('Verified') -or $snapshot.ContainsKey('ok') -or $snapshot.auditoria.validado -isnot [bool] -or -not $snapshot.auditoria.validado){throw 'Snapshot confundido com autorizacao'}
$timestamp=[DateTimeOffset]::Parse($snapshot.criado_utc,[Globalization.CultureInfo]::InvariantCulture)
if($timestamp.Offset -ne [TimeSpan]::Zero){throw 'Timestamp nao UTC'}
$record.artista='Mutado';$record.aprovacao_musical.fixture=$false
$audit.contexto.valor='Mutado';$probe.detalhes.valor='Mutado'
if($snapshot.registro.artista -cne 'AC/DC' -or $snapshot.registro.aprovacao_musical.fixture -ne $true -or $snapshot.auditoria.contexto.valor -cne 'original' -or $snapshot.probe.detalhes.valor -cne 'original'){throw 'Copia profunda falhou'}
$record.artista='AC/DC';$record.aprovacao_musical.fixture=$true
$audit.contexto.valor='original';$probe.detalhes.valor='original'
$badAudit=$audit.Clone();$badAudit.resultado_sha256=('0'*64)
$badRecord=$record.Clone();$badRecord.url_original='https://www.youtube.com/watch?v=OtherVideo1'
$badBool=$audit.Clone();$badBool.validado='True'
$cases=@(
 @{Changes=@{Audit=$badAudit};Type=[IO.InvalidDataException];Message='Hash'},
 @{Changes=@{Record=$badRecord};Type=[IO.InvalidDataException];Message='chave'},
 @{Changes=@{VideoId='testVideo01'};Type=[IO.InvalidDataException];Message='video_id'},
 @{Changes=@{Target=$existing};Type=[IO.IOException];Message='Target'},
 @{Changes=@{Target=(Join-Path $work 'outside.mp3')};Type=[ArgumentException];Message='Target'},
 @{Changes=@{Ready=$outside};Type=[ArgumentException];Message='Control'},
 @{Changes=@{Audit=$badBool};Type=[ArgumentException];Message='Audit'}
)
foreach($case in $cases){
 $parameters=$base.Clone()
 foreach($name in $case.Changes.Keys){$parameters[$name]=$case.Changes[$name]}
 $caught=$false
 try{$null=New-PublicationIntentSnapshot @parameters}
 catch{
  if(-not $case.Type.IsInstanceOfType($_.Exception) -or $_.Exception.Message.IndexOf($case.Message,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw}
  $caught=$true
 }
 if(-not $caught){throw ('Controle negativo aceito: '+$case.Message)}
}
if((Get-FileHash -LiteralPath $ready).Hash.ToLowerInvariant() -cne $expected -or (Get-FileHash -LiteralPath $outside).Hash.ToLowerInvariant() -cne $expected -or (Get-FileHash -LiteralPath $existing).Hash -cne $existingHash -or (Test-Path -LiteralPath $target)){throw 'Snapshot alterou arquivos'}
Write-Output 'INTENCAO_PUBLICACAO_PASS'
