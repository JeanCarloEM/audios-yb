$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$t=$null;$e=$null
$a=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'baixar_audios_ytdlp.ps1'),[ref]$t,[ref]$e)
if($e.Count){throw 'Sintaxe principal'}
$f=@($a.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-Ytdlp'},$true))
. ([scriptblock]::Create($f[0].Extent.Text))
$module=Join-Path $repo 'ferramentas_portateis.ps1'
[void][Management.Automation.Language.Parser]::ParseFile($module,[ref]$t,[ref]$e)
if($e.Count){throw ($e|Out-String)}
. $module
$script:Root=$repo
function Assert($ok,[string]$message){if(-not $ok){throw $message}}
function MustFail([scriptblock]$action,[string]$message){$bad=$false;try{$null=& $action}catch{$bad=$true};Assert $bad $message}
$tools=Resolve-ScriptTools -Root $repo
Assert ($tools.Exe -ceq (Join-Path $repo 'yt-dlp.exe')) 'yt-dlp.exe obrigatorio alterado'
foreach($name in @('Ffmpeg','Ffprobe')){Assert ([IO.File]::Exists($tools[$name])) ('Ferramenta nao resolvida: '+$name)}
$versions=Test-ScriptTools -Tools $tools
foreach($name in @('Exe','Ffmpeg','Ffprobe')){Assert (-not [string]::IsNullOrWhiteSpace($versions[$name])) ('Versao real nao retornada: '+$name)}
$work=Join-Path $repo ('tests/.runtime-tools-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
MustFail {Resolve-ScriptTools -Root $work} 'Ausencia yt-dlp nao rejeitada'
$broken=Join-Path $work 'yt-dlp.exe'
[IO.File]::WriteAllText($broken,'not an executable')
$bad=$tools.Clone();$bad.Exe=$broken
MustFail {Test-ScriptTools -Tools $bad} 'Executavel incompativel nao rejeitado'
$missing=$tools.Clone();$missing.Ffprobe=Join-Path $work 'missing-probe'
MustFail {Test-ScriptTools -Tools $missing} 'Probe ausente nao rejeitado'
$pathBefore=$env:PATH
try{
 $env:PATH=''
 $isolated=Resolve-ScriptTools -Root $repo
 Assert ($isolated.Exe -ceq $tools.Exe -and $isolated.Ffmpeg -ceq $tools.Ffmpeg -and $isolated.Ffprobe -ceq $tools.Ffprobe) 'Ferramentas adjacentes passaram a depender PATH/browser'
 $null=Test-ScriptTools -Tools $isolated
}finally{$env:PATH=$pathBefore}
Assert (-not (Test-Path -LiteralPath (Join-Path $work 'destino'))) 'Descoberta/preflight criou destino'
Write-Output ('TOOLS_PORTATEIS_PASS OS='+[Runtime.InteropServices.RuntimeInformation]::OSDescription+'; versoes reais; ausencia/incompativel/PATH vazio; nao comprova Linux/macOS')
