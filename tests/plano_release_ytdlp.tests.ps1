#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'plano_release_ytdlp.ps1')
$script:Checks=0
function Assert($Ok,[string]$Why){if(-not $Ok){throw $Why};$script:Checks++}
function MustFail($Tag,$Manifest,$Architecture,[string]$Why){
 $failed=$false;try{$null=New-YtdlpReleasePlan -Tag $Tag -Manifest $Manifest -Architecture $Architecture}catch [ArgumentException]{$failed=$true}
 Assert $failed $Why
}
# Nomes de assets: fonte canonica https://github.com/yt-dlp/yt-dlp#release-files.
# Tag/checksums sao fixtures sinteticas; nenhuma release real e atestada aqui.
$a='a'*64;$b='b'*64;$c='c'*64
$manifest=$a+'  yt-dlp.exe'+"`n"+$b+' *yt-dlp_x86.exe'+"`n"+$c+'  yt-dlp_arm64.exe'
$expected=@(
 @{arch='X64';asset='yt-dlp.exe';hash=$a},
 @{arch='X86';asset='yt-dlp_x86.exe';hash=$b},
 @{arch='Arm64';asset='yt-dlp_arm64.exe';hash=$c}
)
foreach($item in $expected){
 $p=New-YtdlpReleasePlan -Tag '2026.01.02' -Manifest $manifest -Architecture $item.arch
 Assert (($p.Keys|Sort-Object) -join '|' -ceq 'architecture|asset_name|manifest_url|platform|release_tag|sha256|target_name|tool|url') 'Envelope exato do plano'
 Assert ($p.asset_name -ceq $item.asset -and $p.sha256 -ceq $item.hash -and $p.architecture -ceq $item.arch) 'Vinculo asset/hash/arquitetura'
 Assert ($p.url -ceq ('https://github.com/yt-dlp/yt-dlp/releases/download/2026.01.02/'+$item.asset)) 'URL canonica com tag literal'
 Assert ($p.manifest_url -ceq 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.01.02/SHA2-256SUMS') 'Manifesto da mesma tag'
 Assert ($p.tool -ceq 'yt-dlp' -and $p.platform -ceq 'Windows' -and $p.target_name -ceq 'yt-dlp.exe' -and $p.release_tag -ceq '2026.01.02') 'Destino compativel com descoberta Windows'
 Assert (-not $p.ContainsKey('origin_verified') -and -not $p.ContainsKey('signature_verified') -and -not $p.ContainsKey('installed')) 'Nao afirmar etapas ainda nao realizadas'
}
foreach($tag in @($null,42,@('v1'),'',' ','latest','LATEST','stable','nightly','master','../v','v/x','v\x','v?x','v#x','v%x','v:x','https://evil.test/x',"v`nx",('x'*129))){MustFail $tag $manifest 'X64' 'Rejeitar tag/canal inseguro'}
foreach($arch in @($null,42,@('X64'),'','x64','ARM64','Arm','Linux','Other')){MustFail '2026.01.02' $manifest $arch 'Rejeitar arquitetura nao declarada literalmente'}
MustFail '2026.01.02' ($a+'  yt-dlp.exe') 'Arm64' 'Nao usar hash de outra arquitetura'
MustFail '2026.01.02' ($manifest+"`n"+$a+' *yt-dlp.exe') 'X64' 'Nao aceitar hash duplicado'
MustFail '2026.01.02' ($a+'  YT-DLP.EXE') 'X64' 'Nome do asset e Ordinal'
$fresh=New-YtdlpReleasePlan -Tag '2026.01.03' -Manifest $manifest -Architecture 'X64'
Assert ($fresh.manifest_url -ceq 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.01.03/SHA2-256SUMS' -and $fresh.url -ceq 'https://github.com/yt-dlp/yt-dlp/releases/download/2026.01.03/yt-dlp.exe') 'Troca de tag vincula ambas URLs'
'YTDLP_RELEASE_PLAN_PASS checks'+$script:Checks+'; fixtures sinteticas, somente Windows, sem rede/assinatura/instalacao'
