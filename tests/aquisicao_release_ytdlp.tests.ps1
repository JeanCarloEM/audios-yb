#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'aquisicao_release_ytdlp.ps1')
# Reutiliza somente classes de transporte simuladas, sem repetir seus 76 testes.
$fixture=Join-Path $PSScriptRoot 'transporte_release_ytdlp.tests.ps1'
if((Get-FileHash -LiteralPath $fixture).Hash -cne 'EBC2EAD9B426D3E1813F14FEAF29DF2FA5064FB19EDAA1908D2145E100D87C03'){throw 'Fixture HTTP mudou'}
$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile($fixture,[ref]$t,[ref]$e)
$c=@($a.FindAll({param($n)$n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value.StartsWith('using System;')},$true))
if($e.Count -or $c.Count -ne 1){throw 'Fixture HTTP ambigua'}
Add-Type -TypeDefinition $c[0].Value
$script:Checks=0
function Assert($Ok,[string]$Why){if(-not $Ok){throw $Why};$script:Checks++}
function MustFail([scriptblock]$Action,[string]$Why){$failed=$false;try{$null=& $Action}catch{$failed=$true};Assert $failed $Why}
function Bytes([string]$Text){return ,[Text.Encoding]::UTF8.GetBytes($Text)}
function ByteHash([byte[]]$Bytes){$sha=[Security.Cryptography.SHA256]::Create();try{return [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function Queue([byte[]]$Meta,[byte[]]$Manifest,[byte[]]$Blob){
 $h=[ReleaseProbeHandler]::new()
 foreach($data in @($Meta,$Manifest,$Blob)){$r=[Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]::OK);$r.Content=[Net.Http.ByteArrayContent]::new($data);$h.Replies.Enqueue($r)}
 return $h
}
# Campos canonicos: https://docs.github.com/en/rest/releases/releases#get-the-latest-release.
# Versao/hash/bytes sinteticos; URL externa em assets nao pode virar instrucao de download.
$meta='{"tag_name":"2026.01.02","draft":false,"prerelease":false,"assets":[{"browser_download_url":"https://evil.test/not-used.exe"}]}'
$blob=Bytes 'abc';$hash='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
$manifest=$hash+'  yt-dlp.exe'+"`n"+$hash+'  yt-dlp_x86.exe'+"`n"+$hash+'  yt-dlp_arm64.exe'
$api='https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest'
$base='https://github.com/yt-dlp/yt-dlp/releases/download/2026.01.02/'
foreach($row in @(@('X64','yt-dlp.exe'),@('X86','yt-dlp_x86.exe'),@('Arm64','yt-dlp_arm64.exe'))){
 $h=Queue (Bytes $meta) (Bytes $manifest) $blob
 $p=Get-YtdlpReleasePackage -Architecture $row[0] -Handler $h
 Assert (($p.Keys|Sort-Object) -join '|' -ceq 'bytes|manifest|manifest_sha256|metadata_sha256|metadata_url|release_plan') 'Envelope fechado do pacote'
 Assert ($p.bytes -is [byte[]] -and [Text.Encoding]::ASCII.GetString($p.bytes) -ceq 'abc' -and $p.release_plan.sha256 -ceq $hash) 'Pacote nao corresponde ao checksum esperado'
 Assert (($h.Seen -join '|') -ceq ($api+'|'+$base+'SHA2-256SUMS|'+$base+$row[1])) 'Sequencia/origem/tag/asset incorretos'
 Assert ($p.metadata_url -ceq $api -and $p.manifest -ceq $manifest -and $p.metadata_sha256 -ceq (ByteHash (Bytes $meta)) -and $p.manifest_sha256 -ceq (ByteHash (Bytes $manifest))) 'Proveniencia deve ligar bytes originais de metadata/manifesto'
 Assert (-not $h.Disposed) 'Pacote descartou transporte externo'
}
foreach($bad in @(
 '{}','[]','null','{"tag_name":"2026.01.02","draft":false}',
 '{"tag_name":42,"draft":false,"prerelease":false}',
 '{"tag_name":"2026.01.02","draft":0,"prerelease":false}',
 '{"tag_name":"2026.01.02","draft":false,"prerelease":"false"}',
 '{"tag_name":"2026.01.02","draft":true,"prerelease":false}',
 '{"tag_name":"2026.01.02","draft":false,"prerelease":true}',
 '{"tag_name":"latest","draft":false,"prerelease":false}',
 '{"tag_name":"../x","draft":false,"prerelease":false}',
 '{"Tag_Name":"2026.01.02","draft":false,"prerelease":false}',
 '{"tag_name":"2026.01.02","Tag_Name":"2026.01.02","draft":false,"prerelease":false}',
 '{"tag_name":"2026.01.02","tag_name":"2026.01.02","draft":false,"prerelease":false}',
 '{"tag_name":"2026.01.02","draft":false,"draft":false,"prerelease":false}'
)){
 $h=Queue (Bytes $bad) (Bytes $manifest) $blob
 MustFail {Get-YtdlpReleasePackage -Architecture X64 -Handler $h} ('Metadata invalida ou ambigua deve falhar: '+$bad)
 Assert ($h.Seen.Count -eq 1) 'Metadata invalida provocou pedido dependente'
}
$h=Queue ([byte[]]@(195,40)) (Bytes $manifest) $blob
MustFail {Get-YtdlpReleasePackage -Architecture X64 -Handler $h} 'UTF8 invalido nao pode ser substituido silenciosamente'
Assert ($h.Seen.Count -eq 1) 'UTF8 invalido provocou pedido dependente'
$prefix=Bytes '{"tag_name":"2026.01.02","draft":false,"prerelease":false,"body":"'
$suffix=Bytes '"}'
$h=Queue ([byte[]]($prefix+[byte[]]@(195,40)+$suffix)) (Bytes $manifest) $blob
MustFail {Get-YtdlpReleasePackage -Architecture X64 -Handler $h} 'UTF8 invalido em campo ignorado deve falhar antes do JSON'
Assert ($h.Seen.Count -eq 1) 'UTF8 substitutivo em campo ignorado foi aceito'
foreach($bad in @('invalido',($hash+'  yt-dlp.exe'+"`n"+$hash+' *yt-dlp.exe'),($hash+'  outra.exe'))){
 $h=Queue (Bytes $meta) (Bytes $bad) $blob
 MustFail {Get-YtdlpReleasePackage -Architecture X64 -Handler $h} 'Manifesto deve ser validado antes do asset'
 Assert ($h.Seen.Count -eq 2) 'Manifesto invalido provocou download do asset'
}
$h=Queue (Bytes $meta) (Bytes $manifest) (Bytes 'bytes divergentes')
MustFail {Get-YtdlpReleasePackage -Architecture X64 -Handler $h} 'Checksum divergente nao pode gerar pacote'
Assert ($h.Seen.Count -eq 3) 'Repetiu pedido apos hash divergente'
foreach($arch in @($null,'','x64','Other')){
 $h=[ReleaseProbeHandler]::new();MustFail {Get-YtdlpReleasePackage -Architecture $arch -Handler $h} 'Arquitetura invalida deve falhar'
 Assert ($h.Seen.Count -eq 0) 'Arquitetura invalida acessou rede'
}
$h=[ReleaseProbeHandler]::new()
MustFail {Get-YtdlpReleasePackage -Architecture @('X64') -Handler $h} 'Arquitetura deve ser string escalar sem coercao'
Assert ($h.Seen.Count -eq 0) 'Tipo de arquitetura invalido provocou pedido'
# Demonstra limite do asset superior ao limite de 1MiB da metadata, sem decodificar binario.
$big=[byte[]]::new(1048577);$big[0]=255;$big[$big.Length-1]=254
$bigManifest=(ByteHash $big)+'  yt-dlp.exe'
$h=Queue (Bytes $meta) (Bytes $bigManifest) $big
$p=Get-YtdlpReleasePackage -Architecture X64 -Handler $h
Assert ($p.bytes.Length -eq $big.Length -and $p.bytes[0] -eq 255 -and $p.bytes[$big.Length-1] -eq 254) 'Asset nao e texto nem metadata de 1MiB'
'YTDLP_RELEASE_PACKAGE_PASS checks'+$script:Checks+'; respostas simuladas e bytes sinteticos, sem IO de artefato/execucao/assinatura'
