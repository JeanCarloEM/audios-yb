#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'ferramentas_portateis.ps1')
$work=Join-Path $PSScriptRoot ('.runtime-native-discovery-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$script:LookupCalls=0;$script:MockAppPath=''
function Get-Command {
 [CmdletBinding()]param([string]$Name,[string]$CommandType)
 if($Name -cne 'yt-dlp' -or $CommandType -ne 'Application'){throw 'Consulta nao autorizada no probe'}
 $script:LookupCalls++
 if($script:MockAppPath){return [pscustomobject]@{Path=$script:MockAppPath}}
 return @()
}
function Assert($Ok,[string]$Why){if(-not $Ok){throw $Why}}
function Case([string]$Name,[string[]]$Files){
 $dir=Join-Path $work $Name;[void][IO.Directory]::CreateDirectory($dir)
 foreach($file in $Files){[IO.File]::WriteAllText((Join-Path $dir $file),'Fixture textual somente para descoberta; nao executar')}
 return $dir
}
$all=Case 'raiz espaço ação' @('yt-dlp.exe','yt-dlp','yt-dlp_linux','yt-dlp_linux_aarch64','yt-dlp_macos')
foreach($c in @(
 @{platform='Windows';arch='X64';name='yt-dlp.exe'},
 @{platform='Linux';arch='X64';name='yt-dlp_linux'},
 @{platform='Linux';arch='Arm64';name='yt-dlp_linux_aarch64'},
 @{platform='macOS';arch='Arm64';name='yt-dlp_macos'},
 @{platform='Linux';arch='Arm';name='yt-dlp'},
 @{platform='Other';arch='X64';name='yt-dlp'}
)){
 $script:LookupCalls=0
 $actual=Find-YtdlpExecutable -Root $all -Platform $c.platform -Architecture $c.arch
 Assert ($actual -ceq (Join-Path $all $c.name)) ('Prioridade nativa incorreta '+$c.platform+'/'+$c.arch)
 Assert ($script:LookupCalls -eq 0) 'PATH consultado apesar de adjacente'
}
$generic=Case 'generico' @('yt-dlp.exe','yt-dlp')
Assert ((Find-YtdlpExecutable -Root $generic -Platform Linux -Architecture X64) -ceq (Join-Path $generic 'yt-dlp')) 'Generico adjacente perdido'
$onlyExe=Case 'somente PE' @('yt-dlp.exe')
$pathDir=Case 'path' @('yt-dlp')
$script:MockAppPath=Join-Path $pathDir 'yt-dlp'
$script:LookupCalls=0
Assert ((Find-YtdlpExecutable -Root $onlyExe -Platform Linux -Architecture X64) -ceq $script:MockAppPath) 'PATH nativo nao descoberto'
Assert ($script:LookupCalls -eq 1) 'Ordem PATH inesperada'
$withoutExe=Case 'windows faltando' @('yt-dlp')
$script:LookupCalls=0;$failed=$false
try{[void](Find-YtdlpExecutable -Root $withoutExe -Platform Windows -Architecture X64)}catch{$failed=$true}
Assert ($failed -and $script:LookupCalls -eq 0) 'Windows relaxou contrato adjacente'
$script:MockAppPath='';$failed=$false
try{[void](Find-YtdlpExecutable -Root $onlyExe -Platform Linux -Architecture X64)}catch{$failed=$true}
Assert $failed 'Nao Windows aceitou apenas PE adjacente'
Assert (-not (Test-Path -LiteralPath (Join-Path $all 'destino'))) 'Descoberta criou destino'
'YTDLP_NATIVE_DISCOVERY_PASS: prioridades parametrizadas Windows/Linux/macOS/Other e arquitetura, generico/PATH, Windows obrigatorio; nao executa binarios de outros sistemas'
