#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'manifesto_sha256.ps1')
$script:Checks=0
function Assert($Ok,[string]$Why){if(-not $Ok){throw $Why};$script:Checks++}
function MustFail($Text,$Name,[string]$Why){
 $failed=$false
 try{$null=Get-ManifestAssetSha256 -Manifest $Text -AssetName $Name}catch [ArgumentException]{$failed=$true}
 Assert $failed $Why
}
# Formato GNU publicado pelo yt-dlp: https://github.com/yt-dlp/yt-dlp#release-files
# Fixture sintetica independente do helper: SHA-256 do texto ASCII abc, vetor conhecido.
# Nao e checksum de uma release real nem comprovacao de assinatura/procedencia.
$abc='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
$zero='0'*64
$text=$zero+'  yt-dlp.exe.bak'+"`n"+$abc+'  yt-dlp.exe'+"`n"+$zero+' *yt-dlp_linux'
Assert ((Get-ManifestAssetSha256 -Manifest $text -AssetName 'yt-dlp.exe') -ceq $abc) 'Selecionar basename exato, nao prefixo/primeiro'
Assert ((Get-ManifestAssetSha256 -Manifest ($abc.ToUpperInvariant()+' *yt-dlp.exe') -AssetName 'yt-dlp.exe') -ceq $abc) 'GNU binario e hex maiusculo'
Assert ((Get-ManifestAssetSha256 -Manifest ($text.Replace("`n","`r`n")+"`r`n") -AssetName 'yt-dlp_linux') -ceq $zero) 'CRLF e linha final vazia'
MustFail ($abc+'  YT-DLP.EXE') 'yt-dlp.exe' 'Comparacao deve ser Ordinal'
MustFail ($abc+'  yt-dlp.exe.bak') 'yt-dlp.exe' 'Nao aceitar sufixo'
MustFail ($abc+'  yt-dlp.exe'+"`n"+$abc+' *yt-dlp.exe') 'yt-dlp.exe' 'Duplicata mesmo hash nao e unica'
MustFail ($abc+'  yt-dlp.exe'+"`n"+$zero+'  yt-dlp.exe') 'yt-dlp.exe' 'Duplicata conflitante'
foreach($line in @(
 ($abc.Substring(1)+'  yt-dlp.exe'),($abc+'0  yt-dlp.exe'),('z'+$abc.Substring(1)+'  yt-dlp.exe'),
 ($abc+' ?yt-dlp.exe'),($abc+"`t yt-dlp.exe"),($abc+' yt-dlp.exe'),($abc+'  '),
 ($abc+'  ./yt-dlp.exe'),($abc+'  dir/yt-dlp.exe'),($abc+'  dir\yt-dlp.exe'),($abc+'  yt-dlp.exe '),
 ($abc+'  yt-dlp.exe'+"`r"),($abc+'  yt-dlp.exe'+[char]0),($abc+'  yt-dlp.exe'+"`n"+'linha invalida')
)){MustFail $line 'yt-dlp.exe' 'Rejeitar sintaxe/nomes/campos invalidos'}
foreach($name in @($null,42,@('yt-dlp.exe'),'',' ','.','..','../x','x/y','x\y','C:x',"x`ny",('a'*256))){MustFail ($abc+'  yt-dlp.exe') $name 'Rejeitar asset inseguro ou tipo invalido'}
foreach($manifest in @($null,42,@('x'),'',' ',("`n"*3),('a'*(1MB+1)))){MustFail $manifest 'yt-dlp.exe' 'Rejeitar manifesto ausente/invalido/excessivo'}
Assert (([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::ASCII.GetBytes('abc')))).ToLowerInvariant() -ceq $abc) 'Fixture SHA256 deve coincidir com vetor independente'
'RELEASE_MANIFEST_SHA256_PASS checks'+$script:Checks+'; somente parsing GNU de basenames, nao autenticacao/download/instalacao'
