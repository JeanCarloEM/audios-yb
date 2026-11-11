#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'indice_artefatos_ffmpeg.ps1')
$script:Checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:Checks++}
function MustFail([object]$Json){$failed=$false;try{$null=Read-FfmpegAssetIndex -Json $Json}catch{$failed=$true};Assert $failed 'Metadata invalida aceita'}
$header='"tag_name":"autobuild-2026-11-10-12-39","draft":false,"prerelease":false'
# Nomes literais da release; digests sinteticos explicitamente separados dos reais.
# https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/tag/autobuild-2026-11-10-12-39
$name='ffmpeg-n9.0.2-48-gd4070a14ce-win64-lgpl-9.0.zip'
$asset='{"name":"'+$name+'","size":168579921,"digest":"sha256:'+('A'*64)+'","id":123}'
$json='{'+$header+',"assets":['+$asset+',{"name":"checksums.sha256","size":5728,"digest":null},{"name":"legacy.txt","size":0}],"body":"ignorado"}'
$result=Read-FfmpegAssetIndex -Json $json
Assert ($result -is [hashtable] -and $result.Count -eq 2) 'Retorno deve ser mapa unico de2campos'
Assert ($result.release_tag -is [string] -and $result.release_tag -ceq 'autobuild-2026-11-10-12-39') 'Tag incorreta'
Assert ($result.assets -is [Array] -and $result.assets.Count -eq 3) 'Indice deve conter tres registros'
$first=$result.assets[0]
Assert ($first -is [hashtable] -and $first.Count -eq 3 -and $first.name -is [string] -and $first.name -ceq $name) 'Registro/name incorreto'
Assert ($first.size -is [long] -and $first.size -eq 168579921) 'Size deve ser Int64 exato'
Assert ($first.sha256 -is [string] -and $first.sha256 -ceq ('a'*64)) 'Digest deve resultar em SHA256 minusculo'
Assert ($null -eq $result.assets[1].sha256 -and $null -eq $result.assets[2].sha256) 'Digest null/ausente deve preservar ausencia de prova'
Assert ($result.assets[2].size -is [long] -and $result.assets[2].size -eq 0) 'Size0 e um fato, nao prova de prontidao'
foreach($bad in @(
    '{"name":"x"}', '{"name":"x","size":-1}', '{"name":"x","size":1.5}',
    '{"name":"x","size":9223372036854775808}', '{"name":"x","size":"1"}',
    '{"name":"x","size":1,"digest":42}', '{"name":"x","size":1,"digest":"sha256:bad"}',
    '{"name":"x","Name":"x","size":1}', '{"name":"x","name":"x","size":1}',
    '{"name":"x","nAmE":"x","size":1}', '{"name":"x","size":1,"diGest":null}',
    '{"name":"x","size":1,"size":2}', '{"name":"x","Size":1}',
    '{"name":"x","size":1,"Digest":null}', '{"name":"x","size":1,"digest":null,"digest":null}',
    '{"name":null,"size":1}', '{"name":42,"size":1}', '{"name":" ","size":1}', '42'
)){MustFail ('{'+$header+',"assets":['+$asset+','+$bad+']}')}
foreach($rootJson in @(
    ('{'+$header+'}'), ('{'+$header+',"assets":[]}'), ('{'+$header+',"assets":{}}'),
    ('{'+$header+',"assets":['+$asset+'],"Assets":['+$asset+']}'),
    ('{'+$header+',"assets":['+$asset+'],"assets":['+$asset+']}'),
    ('{'+$header+',"assets":['+$asset+','+$asset+']}'),
    ('{'+$header.Replace('"draft":false','"draft":true')+',"assets":['+$asset+']}'),
    ('{'+$header.Replace('autobuild-2026-11-10-12-39','autobuild-2026-02-30-12-39')+',"assets":['+$asset+']}'),
    ('{'+$header.Replace('autobuild-2026-11-10-12-39','latest')+',"assets":['+$asset+']}')
)){MustFail $rootJson}
$extra=@(1..256|ForEach-Object {'{"name":"other-'+$_+'","size":0}'})
Assert ($extra.Count -eq 256) 'Fixture257 incorreta'
MustFail ('{'+$header+',"assets":['+$asset+','+($extra -join ',')+']}')
foreach($invalid in @($null,123,'','[ ]','{')){MustFail $invalid}
Write-Output "FFMPEG_ASSET_INDEX_PASS checks$script:Checks"
