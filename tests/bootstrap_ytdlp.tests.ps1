#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$work=Join-Path $PSScriptRoot ('.runtime-ytdlp-bootstrap-'+[guid]::NewGuid().ToString('N'))
$moduleRoot=Join-Path $work 'module';[void][IO.Directory]::CreateDirectory($moduleRoot)
[IO.File]::Copy((Join-Path $repo 'ferramentas_portateis.ps1'),(Join-Path $moduleRoot 'ferramentas_portateis.ps1'))
$fake=@'
function Install-YtdlpDependency([string]$Root){
 $global:YtdlpBootstrapProbe.Calls+=,$Root
 if($global:YtdlpBootstrapProbe.Fail){throw 'fixture-installer-failure'}
 if(-not $global:YtdlpBootstrapProbe.SkipWrite){[IO.File]::WriteAllText((Join-Path $Root 'yt-dlp.exe'),'fixture tool, nao executar')}
 return @{version='fixture';publication=@{status='published'}}
}
'@
[IO.File]::WriteAllText((Join-Path $moduleRoot 'instalacao_ytdlp.ps1'),$fake)
. (Join-Path $moduleRoot 'ferramentas_portateis.ps1')
$script:Checks=0
function Assert($Ok,[string]$Why){if(-not $Ok){throw $Why};$script:Checks++}
function MustFail([scriptblock]$Call,[string]$Why){$failed=$false;try{$null=& $Call}catch{$failed=$true};Assert $failed $Why}
function New-Case([string]$Name){
 $p=Join-Path $work $Name;[void][IO.Directory]::CreateDirectory($p)
 foreach($name in @('ffmpeg.exe','ffprobe.exe')){[IO.File]::WriteAllText((Join-Path $p $name),'discovery fixture')}
 $global:YtdlpBootstrapProbe=@{Calls=@();Fail=$false;SkipWrite=$false}
 return $p
}
$root=New-Case 'default-off'
MustFail {Resolve-ScriptTools -Root $root} 'Sem switch manter rejeicao de yt-dlp ausente'
Assert ($global:YtdlpBootstrapProbe.Calls.Count -eq 0 -and -not [IO.File]::Exists((Join-Path $root 'yt-dlp.exe'))) 'Bootstrap nao pode ligar implicitamente'
$root=New-Case 'missing'
$tools=Resolve-ScriptTools -Root $root -BootstrapYtdlp
Assert ($global:YtdlpBootstrapProbe.Calls.Count -eq 1 -and $global:YtdlpBootstrapProbe.Calls[0] -ceq $root) 'Instalador local deve receber Root exato uma vez'
Assert ($tools.Exe -ceq (Join-Path $root 'yt-dlp.exe') -and $tools.YtdlpBootstrap.version -ceq 'fixture') 'Redescobrir exe e devolver recibo sem mudar campos existentes'
$root=New-Case 'existing';$target=Join-Path $root 'yt-dlp.exe';[IO.File]::WriteAllText($target,'usuario')
$tools=Resolve-ScriptTools -Root $root -BootstrapYtdlp
Assert ($global:YtdlpBootstrapProbe.Calls.Count -eq 0 -and [IO.File]::ReadAllText($target) -ceq 'usuario' -and -not $tools.ContainsKey('YtdlpBootstrap')) 'Preservar existente sem tentar atualizar'
$root=New-Case 'failure';$global:YtdlpBootstrapProbe.Fail=$true
MustFail {Resolve-ScriptTools -Root $root -BootstrapYtdlp} 'Propagar falha do instalador'
Assert ($global:YtdlpBootstrapProbe.Calls.Count -eq 1 -and -not [IO.File]::Exists((Join-Path $root 'yt-dlp.exe'))) 'Nao repetir ou aceitar falha'
$root=New-Case 'no-file';$global:YtdlpBootstrapProbe.SkipWrite=$true
MustFail {Resolve-ScriptTools -Root $root -BootstrapYtdlp} 'Recibo sozinho nao comprova ferramenta disponivel'
Assert ($global:YtdlpBootstrapProbe.Calls.Count -eq 1) 'Nao repetir instalacao incompleta'
# Executa somente a atribuicao real de startup, sem disparar lote/rede.
$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'baixar_audios_ytdlp.ps1'),[ref]$t,[ref]$e)
$tries=@($a.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})
if($e.Count -or $tries.Count -ne 1){throw 'Startup ambiguo'}
$st=@($tries[0].Body.Statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left -is [Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'tools'})
if($st.Count -ne 1){throw 'Atribuicao tools ambigua'}
$script:Root=New-Case 'main-startup'
. ([scriptblock]::Create($st[0].Extent.Text))
Assert ($global:YtdlpBootstrapProbe.Calls.Count -eq 1 -and $tools.Exe -ceq (Join-Path $script:Root 'yt-dlp.exe')) 'Principal deve habilitar bootstrap no resolver'
'YTDLP_BOOTSTRAP_STARTUP_PASS checks'+$script:Checks+'; instalador simulado/IO real/atribuicao startup real, sem rede/execucao; '+$work
