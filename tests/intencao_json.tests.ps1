#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1.0
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'publicacao_pendente.ps1')
$iso='2026-11-06T12:00:00.0000000Z'
$json='{"title":"2026-11-06T12:00:00.0000000Z","day":"2026-11-06","offset":"2026-11-06T12:00:00+01:00","empty":[],"one":[1],"nested":[["x"],[]],"nothing":null,"no":false,"yes":true,"artist":"AC/DC","Artist":"DJ","unicode":"Colet\u00e2nea","nul":"A\u0000B","fraction":1.25,"max":9223372036854775807}'
$data=ConvertFrom-PublicationJson -Json $json
if($data -isnot [hashtable] -or $data.title -isnot [string] -or -not [string]::Equals($data.title,$iso,[StringComparison]::Ordinal) -or $data.day -isnot [string] -or $data.offset -isnot [string]){throw 'Strings de datas convertidas'}
if($data.artist -cne 'AC/DC' -or $data.Artist -cne 'DJ' -or $data.ContainsKey('ARTIST')){throw 'Comparador de chaves nao Ordinal'}
if($data.empty -isnot [object[]] -or $data.empty.Count -ne 0 -or $data.one -isnot [object[]] -or $data.one.Count -ne 1 -or $data.one[0] -ne 1){throw 'Arrays vazios/unitarios deformados'}
if($data.nested.Count -ne 2 -or $data.nested[0] -isnot [object[]] -or $data.nested[0][0] -cne 'x' -or $data.nested[1].Count -ne 0){throw 'Arrays aninhados deformados'}
if($null -ne $data.nothing -or $data.no -isnot [bool] -or $data.no -or $data.yes -isnot [bool] -or -not $data.yes -or $data.max -ne [long]::MaxValue -or $data.fraction -ne 1.25){throw 'Primitivos deformados'}
if(-not [string]::Equals($data.unicode,('Colet'+[char]0x00E2+'nea'),[StringComparison]::Ordinal) -or -not [string]::Equals($data.nul,('A'+[char]0+'B'),[StringComparison]::Ordinal)){throw 'Unicode ou NUL alterado'}
$empty=ConvertFrom-PublicationJson -Json '{}'
if($empty -isnot [hashtable] -or $empty.Count -ne 0){throw 'Objeto vazio perdido'}
$bad=@('[]','{"x":1,"x":2}','{"x":9223372036854775808}','{"x":1e400}','{"x":}','{"x":1,}',(('{"x":'*70)+'0'+('}'*70)))
foreach($value in $bad){
 $caught=$false
 try{$null=ConvertFrom-PublicationJson -Json $value}catch [IO.InvalidDataException]{$caught=$true}
 if(-not $caught){throw 'JSON invalido/nao suportado aceito'}
}
# Quatro bytes NAO audio; validamos preservacao de dados, nunca qualidade/aprovacao real.
$work=Join-Path $PSScriptRoot ('.runtime-intencao-json-'+[guid]::NewGuid().ToString('N'))
$out=Join-Path $work 'out'
$control=Join-Path $out '.controle'
$fontes=Join-Path $control 'fontes'
$null=New-Item -ItemType Directory -Path $fontes
$ready=Join-Path $fontes 'source.mp3'
$bytes=[byte[]]@(0,1,2,255)
[IO.File]::WriteAllBytes($ready,$bytes)
$sha=[Security.Cryptography.SHA256]::Create()
try{
 $expectedHash=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
 $keyText=[string]::Join([char]31,@('1','AC/DC',$iso,'https://www.youtube.com/watch?v=TestVideo01'))
 $key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($keyText))).Replace('-','').ToLowerInvariant()
}finally{$sha.Dispose()}
$record=@{chave=$key;ordem='1';artista='AC/DC';musica=$iso;url_original='https://www.youtube.com/watch?v=TestVideo01';video_id='TestVideo01';aprovacao_musical=@{fixture=$true;timestamp=$iso};candidatos=@();rejeicoes=@(@{motivo='fixture'})}
$audit=@{validado=$true;politica='fixture-v1';origem_sha256=('a'*64);resultado_sha256=$expectedHash;timestamp=$iso}
$probe=@{fixture=$true;timestamp=$iso}
$snapshot=New-PublicationIntentSnapshot -Ready $ready -Target (Join-Path $out 'final.mp3') -Control $control -Out $out -VideoId 'TestVideo01' -Record $record -Audit $audit -Probe $probe
if($snapshot.registro.musica -isnot [string] -or $snapshot.registro.musica -cne $iso -or $snapshot.registro.aprovacao_musical.timestamp -isnot [string] -or $snapshot.auditoria.timestamp -isnot [string] -or $snapshot.probe.timestamp -isnot [string]){throw 'Snapshot mudou tipos de data'}
if($snapshot.registro.candidatos.Count -ne 0 -or $snapshot.registro.rejeicoes.Count -ne 1){throw 'Snapshot perdeu arrays'}
$saved=Save-PublicationIntentFile -Snapshot $snapshot -Control $control -Out $out
$loaded=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($saved.Path))
if($loaded.registro.musica -isnot [string] -or $loaded.registro.musica -cne $iso -or $loaded.registro.aprovacao_musical.timestamp -isnot [string] -or $loaded.criado_utc -isnot [string] -or $loaded.persistido_utc -isnot [string] -or $loaded.registro.chave -cne $key -or $loaded.status -cne 'preparada'){throw 'Persistencia mudou texto/identidade'}
if((Get-FileHash -LiteralPath $ready).Hash.ToLowerInvariant() -cne $expectedHash -or (Test-Path -LiteralPath (Join-Path $out 'final.mp3'))){throw 'Dados alterados ou audio publicado'}
Write-Output 'INTENCAO_JSON_PASS'
