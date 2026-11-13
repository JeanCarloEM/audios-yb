#requires -Version 7.0
$ErrorActionPreference='Stop';$repo=Split-Path -Parent $PSScriptRoot;$checks=0
function Assert($ok,$why){if(!$ok){throw $why};$script:checks++}
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'baixar_audios_ytdlp.ps1'),[ref]$tokens,[ref]$errors)
$tries=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})
if($errors.Count -ne 0 -or $tries.Count -ne 1){throw 'Startup ambíguo ou sintaxe inválida'}
$assign=@($tries[0].Body.Statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst]})
$begin=@($assign|Where-Object {$_.Left -is [Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'tools'})
$end=@($assign|Where-Object {$_.Left -is [Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'versions'})
if($begin.Count -ne 1 -or $end.Count -ne 1){throw 'Atribuições de startup ambíguas'}
$selected=@($tries[0].Body.Statements|Where-Object {$_.Extent.StartOffset -ge $begin[0].Extent.StartOffset -and $_.Extent.EndOffset -le $end[0].Extent.EndOffset})
$names=@($selected|ForEach-Object {if($_ -isnot [Management.Automation.Language.AssignmentStatementAst] -or $_.Left -isnot [Management.Automation.Language.VariableExpressionAst]){throw 'Statement inesperado'};$_.Left.VariablePath.UserPath})
Assert (($names -join ',') -ceq 'tools,script:Exe,script:Ffmpeg,script:Ffprobe,versions') 'Ordem real: resolver -> caminhos -> verificação'
foreach($statement in $selected){foreach($command in $statement.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true)){if($command.GetCommandName() -cnotin @('Resolve-ScriptTools','Test-ScriptTools')){throw 'Comando inesperado no trecho'}}}
$script:startupCalls=0;$script:startupVerified=0;$script:Root=$repo
function Resolve-ScriptTools([string]$Root,[switch]$BootstrapYtdlp,[switch]$BootstrapFfmpeg){
 Assert ($Root -ceq $repo -and $BootstrapYtdlp -and $BootstrapFfmpeg) 'Startup habilita ambos os bootstraps no Root real'
 $script:startupCalls++;return @{Exe=(Join-Path $Root 'yt-dlp.exe');Ffmpeg=(Join-Path $Root 'ffmpeg.exe');Ffprobe=(Join-Path $Root 'ffprobe.exe');Node=''}
}
function Test-ScriptTools([hashtable]$Tools){$script:startupVerified++;return @{Exe='mock-version';Ffmpeg='mock-version';Ffprobe='mock-version'}}
# Apenas as cinco atribuições reais acima; resolver/verificador são mocks sem IO.
. ([scriptblock]::Create(($selected|ForEach-Object {$_.Extent.Text}) -join "`n"))
Assert ($script:Exe -ceq (Join-Path $repo 'yt-dlp.exe') -and $script:Ffmpeg -ceq (Join-Path $repo 'ffmpeg.exe') -and $script:Ffprobe -ceq (Join-Path $repo 'ffprobe.exe')) 'Caminhos propagados'
Assert ($script:startupCalls -eq 1 -and $script:startupVerified -eq 1 -and $versions.Ffmpeg -ceq 'mock-version') 'Uma resolução seguida da verificação'
Write-Output "FFMPEG_BOOTSTRAP_STARTUP_PASS checks=$checks; AST real/mocks, sem lote/rede/binario real"
