#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1.0
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'publicacao_pendente.ps1')
# Documentos sinteticos: nao existe audio/prova humana validada nesta fixture.
$work=Join-Path $PSScriptRoot ('.runtime-intencao-leitura-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $work
function Get-FixtureDigest([byte[]]$Bytes){
 $sha=[Security.Cryptography.SHA256]::Create()
 try{return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
$filename=(Get-FixtureDigest -Bytes ([Text.Encoding]::UTF8.GetBytes('TestVideo01')))+'.json'
$json='{"schema":"audios-yb-publication-intent/v1","status":"preparada","video_id":"TestVideo01","pronto_relativo":"fontes/source.mp3","arquivo":"final.mp3","tamanho":4,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","registro":{"video_id":"TestVideo01","musica":"2026-11-06T12:00:00.0000000Z"},"auditoria":{"fixture":true},"probe":{"fixture":true},"criado_utc":"2026-11-06T12:00:00.0000000Z","persistido_utc":"2026-11-06T12:00:01.0000000Z"}'
function New-ReaderFixture([string]$Name,[byte[]]$Bytes,[string]$Leaf=$filename){
 $control=Join-Path (Join-Path $work $Name) '.controle'
 $directory=Join-Path $control 'publicacoes_pendentes'
 $null=New-Item -ItemType Directory -Path $directory
 $path=Join-Path $directory $Leaf
 [IO.File]::WriteAllBytes($path,$Bytes)
 return @{Path=$path;Control=$control;ExpectedSha256=(Get-FixtureDigest -Bytes $Bytes)}
}
$valid=New-ReaderFixture -Name 'valid' -Bytes ([Text.Encoding]::UTF8.GetBytes($json))
$result=Read-PublicationIntentFile @valid
if($result.Status -cne 'dados_lidos_nao_autorizados' -or $result.Sha256 -cne $valid.ExpectedSha256 -or -not [string]::Equals($result.Path,$valid.Path,[StringComparison]::Ordinal)){throw 'Leitura retornou contrato incorreto'}
if($result.Data.video_id -cne 'TestVideo01' -or $result.Data.registro.musica -isnot [string] -or $result.Data.registro.musica -cne '2026-11-06T12:00:00.0000000Z' -or $result.Data.persistido_utc -isnot [string] -or $result.ContainsKey('Verified') -or $result.ContainsKey('ok')){throw 'Leitura mudou dados ou declarou autorizacao'}
$wrongHash=$valid.Clone()
$wrongHash.ExpectedSha256=if($valid.ExpectedSha256[0] -ceq '0'){'1'+$valid.ExpectedSha256.Substring(1)}else{'0'+$valid.ExpectedSha256.Substring(1)}
$badSchema=$json.Replace('audios-yb-publication-intent/v1','audios-yb-publication-intent/v1\u00ad')
$schema=New-ReaderFixture -Name 'schema' -Bytes ([Text.Encoding]::UTF8.GetBytes($badSchema))
$renamed=New-ReaderFixture -Name 'renamed' -Bytes ([Text.Encoding]::UTF8.GetBytes($json)) -Leaf 'wrong.json'
$utf8=New-ReaderFixture -Name 'utf8' -Bytes ([byte[]]@(255,254,255))
$oversize=New-ReaderFixture -Name 'large' -Bytes ([byte[]]@(0))
$stream=[IO.File]::Open($oversize.Path,[IO.FileMode]::Open,[IO.FileAccess]::Write)
try{$stream.SetLength(8388609)}finally{$stream.Dispose()}
$outside=$valid.Clone()
$outside.Path=Join-Path $work 'outside.json'
[IO.File]::WriteAllText($outside.Path,$json,[Text.UTF8Encoding]::new($false))
$cases=@(
 @{Args=$wrongHash;Type=[IO.InvalidDataException];Message='Hash'},
 @{Args=$schema;Type=[IO.InvalidDataException];Message='Schema'},
 @{Args=$renamed;Type=[IO.InvalidDataException];Message='Nome'},
 @{Args=$utf8;Type=[IO.InvalidDataException];Message='UTF8'},
 @{Args=$oversize;Type=[IO.InvalidDataException];Message='Tamanho'},
 @{Args=$outside;Type=[ArgumentException];Message='diretorio'}
)
foreach($case in $cases){
 $caught=$false;$arguments=$case.Args
 try{$null=Read-PublicationIntentFile @arguments}
 catch{
  if(-not $case.Type.IsInstanceOfType($_.Exception) -or $_.Exception.Message.IndexOf($case.Message,[StringComparison]::OrdinalIgnoreCase) -lt 0){throw}
  $caught=$true
 }
 if(-not $caught){throw ('Controle negativo aceito: '+$case.Message)}
}
if($IsWindows){
 $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
 if(-not [string]::Equals(([IO.DriveInfo]::new([IO.Path]::GetPathRoot($tempRoot))).DriveFormat,'NTFS',[StringComparison]::OrdinalIgnoreCase)){throw 'Teste Junction exige temporario NTFS'}
 $linkParent=[IO.Path]::GetFullPath([IO.Path]::Combine($tempRoot,('audios-yb-reader-link-'+[guid]::NewGuid().ToString('N'))))
 if(-not [string]::Equals([IO.Path]::GetDirectoryName($linkParent),[IO.Path]::TrimEndingDirectorySeparator($tempRoot),[StringComparison]::OrdinalIgnoreCase)){throw 'Link fora do temporario'}
 $null=[IO.Directory]::CreateDirectory($linkParent)
 $link=Join-Path $linkParent 'control'
 $null=New-Item -ItemType Junction -Path $link -Target $valid.Control
 $caught=$false
 try{$null=Read-PublicationIntentFile -Path (Join-Path (Join-Path $link 'publicacoes_pendentes') $filename) -Control $link -ExpectedSha256 $valid.ExpectedSha256}catch [NotSupportedException]{$caught=$true}
 if(-not $caught){throw 'Leitura seguiu Junction'}
}else{Write-Output 'LEITURA_JUNCAO_NAO_TESTADA_NESTE_SO'}
if((Get-FileHash -LiteralPath $valid.Path).Hash.ToLowerInvariant() -cne $valid.ExpectedSha256){throw 'Leitura modificou intencao original'}
Write-Output 'INTENCAO_LEITURA_PASS'
