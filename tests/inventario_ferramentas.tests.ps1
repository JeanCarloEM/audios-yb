#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'ferramentas_portateis.ps1')
. (Join-Path $repo 'inventario_ferramentas.ps1')
$work=Join-Path $PSScriptRoot ('.runtime-inventory-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$script:Apps=@{};$script:Lookups=@();$script:Checks=0
function Get-Command {
 [CmdletBinding()]param([string]$Name,[string]$CommandType)
 if($CommandType -cne 'Application'){throw 'Inventario consultou algo diferente de Application'}
 $script:Lookups+=,$Name
 if($script:Apps.ContainsKey($Name)){return [pscustomobject]@{Path=$script:Apps[$Name]}}
 return @()
}
function Assert($Ok,[string]$Why){if(-not $Ok){throw $Why};$script:Checks++}
function New-Case([string]$Name,[string[]]$Files){
 $dir=Join-Path $work $Name;[void][IO.Directory]::CreateDirectory($dir)
 foreach($f in $Files){[IO.File]::WriteAllText((Join-Path $dir $f),'Somente descoberta: fixture textual nao executavel')}
 return $dir
}
function Assert-Shape($Value){
 Assert (($Value.Keys|Sort-Object) -join '|' -ceq 'execution_checked|integrity_checked|missing|required_missing|tools') 'Envelope do inventario'
 Assert (($Value.tools.Keys|Sort-Object) -join '|' -ceq 'Exe|Ffmpeg|Ffprobe|Node') 'Chaves de ferramentas'
 Assert ($Value.missing -is [Collections.IList] -and $Value.required_missing -is [Collections.IList]) 'Ausencias devem ser listas, inclusive vazias'
 Assert ($Value.execution_checked -is [bool] -and -not $Value.execution_checked -and $Value.integrity_checked -is [bool] -and -not $Value.integrity_checked) 'Descoberta nao comprova execucao/integridade'
}
$empty=New-Case 'empty' @()
$i=Get-ScriptToolInventory -Root $empty -Platform Windows
Assert-Shape $i
Assert (($i.missing -join '|') -ceq 'Exe|Ffmpeg|Ffprobe|Node') 'Nao coletou todas as ausencias'
Assert (($i.required_missing -join '|') -ceq 'Exe|Ffmpeg|Ffprobe') 'Node opcional no contrato atual'
Assert (@($i.tools.Values|Where-Object {$_ -cne ''}).Count -eq 0) 'Caminho inventado para ferramenta ausente'
$all=New-Case 'all' @('yt-dlp.exe','ffmpeg.exe','ffprobe.exe','node.exe')
$before=@(Get-ChildItem -LiteralPath $all -File|Sort-Object Name|ForEach-Object {$_.Name+':'+(Get-FileHash -LiteralPath $_.FullName).Hash})
$script:Lookups=@()
$i=Get-ScriptToolInventory -Root $all -Platform Windows
Assert-Shape $i
Assert ($i.missing.Count -eq 0 -and $i.required_missing.Count -eq 0 -and $script:Lookups.Count -eq 0) 'Local deve preceder PATH'
foreach($entry in @(@('Exe','yt-dlp.exe'),@('Ffmpeg','ffmpeg.exe'),@('Ffprobe','ffprobe.exe'),@('Node','node.exe'))){Assert ($i.tools[$entry[0]] -ceq (Join-Path $all $entry[1])) ('Caminho local '+$entry[0])}
if($IsWindows){
 $old=Resolve-ScriptTools -Root $all
 foreach($key in $old.Keys){Assert ($old[$key] -ceq $i.tools[$key]) ('Compatibilidade resolver '+$key)}
 $failed=$false;try{$null=Resolve-ScriptTools -Root $empty}catch{$failed=$true}
 Assert $failed 'Resolver legado deve continuar falhando quando obrigatoria ausente'
}
$pathRoot=New-Case 'path' @('app')
foreach($name in @('yt-dlp','ffmpeg','ffprobe','node')){$script:Apps[$name]=Join-Path $pathRoot 'app'}
$script:Lookups=@()
$i=Get-ScriptToolInventory -Root $empty -Platform Windows
Assert-Shape $i
Assert (($i.required_missing -join '|') -ceq 'Exe' -and ($i.missing -join '|') -ceq 'Exe') 'Windows exige yt-dlp local, demais podem vir PATH'
Assert ($script:Lookups -cnotcontains 'yt-dlp') 'Nao ampliar regra Windows do yt-dlp'
foreach($key in @('Ffmpeg','Ffprobe','Node')){Assert ($i.tools[$key] -ceq (Join-Path $pathRoot 'app')) ('PATH '+$key)}
$script:Apps=@{}
foreach($entry in @(@('Linux','Arm64','yt-dlp_linux_aarch64'),@('Linux','X64','yt-dlp_linux'),@('macOS','Arm64','yt-dlp_macos'),@('Other','X64','yt-dlp'))){
 $dir=New-Case ($entry[0]+$entry[1]) @($entry[2],'ffmpeg','ffprobe','node')
 $i=Get-ScriptToolInventory -Root $dir -Platform $entry[0] -Architecture $entry[1]
 Assert-Shape $i
 Assert ($i.missing.Count -eq 0 -and $i.tools.Exe -ceq (Join-Path $dir $entry[2])) ('Nomes nativos '+$entry[0]+$entry[1])
}
$script:Apps=@{ffmpeg=(Join-Path $work 'inexistente')}
$i=Get-ScriptToolInventory -Root $empty -Platform Windows
Assert ($i.tools.Ffmpeg -ceq '' -and $i.missing -ccontains 'Ffmpeg') 'PATH inexistente nao e descoberta valida'
$script:Apps=@{}
$i=Get-ScriptToolInventory -Root $empty -Platform Linux -Architecture X64
Assert (($i.required_missing -join '|') -ceq 'Exe|Ffmpeg|Ffprobe') 'Ausencias obrigatorias tambem fora do Windows'
foreach($entry in @(@('Linux','X64'),@('Linux','Arm64'),@('Linux','X86'),@('macOS','Arm64'))){
 $dir=New-Case ('fallback-'+$entry[0]+$entry[1]) @('yt-dlp')
 $i=Get-ScriptToolInventory -Root $dir -Platform $entry[0] -Architecture $entry[1]
 Assert ($i.tools.Exe -ceq (Join-Path $dir 'yt-dlp') -and $i.missing -cnotcontains 'Exe') ('Fallback local generico '+$entry[0]+$entry[1])
}
$script:Apps=@{'yt-dlp'=(Join-Path $pathRoot 'app')}
$i=Get-ScriptToolInventory -Root $empty -Platform Linux -Architecture X64
Assert ($i.tools.Exe -ceq (Join-Path $pathRoot 'app') -and $i.missing -cnotcontains 'Exe') 'Fallback PATH yt-dlp fora do Windows'
$bad=$false;try{$null=Get-ScriptToolInventory -Root ' ' -Platform Windows}catch{$bad=$true};Assert $bad 'Root vazio deve falhar sem adotar cwd'
$after=@(Get-ChildItem -LiteralPath $all -File|Sort-Object Name|ForEach-Object {$_.Name+':'+(Get-FileHash -LiteralPath $_.FullName).Hash})
Assert (($before -join '|') -ceq ($after -join '|')) 'Inventario alterou ferramentas locais'
'TOOL_INVENTORY_PASS checks'+$script:Checks+'; '+$work
