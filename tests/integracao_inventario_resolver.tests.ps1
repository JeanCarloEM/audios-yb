#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$module=Join-Path $repo 'ferramentas_portateis.ps1'
. $module
$work=Join-Path $PSScriptRoot ('.runtime-inventory-resolver-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$copy=Join-Path $work 'ferramentas_portateis.ps1'
[IO.File]::Copy($module,$copy)
$ps=[PowerShell]::Create()
try{
 $null=$ps.AddScript(@'
param($Module,$Root)
. $Module
function Get-Command {[CmdletBinding()]param($Name,$CommandType);return @()}
$caught='';try{$null=Resolve-ScriptTools -Root $Root}catch{$caught=$_.Exception.Message}
if($caught -cne 'Ferramentas obrigatorias ausentes: yt-dlp, ffmpeg, ffprobe.'){throw ('Diagnostico incompleto: '+$caught)}
if(Test-Path -LiteralPath (Join-Path $Root 'destino')){throw 'Resolver criou destino'}
'INVENTORY_RESOLVER_ISOLATED_PASS'
'@).AddArgument($copy).AddArgument($work)
 $out=@($ps.Invoke())
 # HadErrors tambem sinaliza throw de funcao capturado pelo catch esperado acima.
 if($ps.InvocationStateInfo.State -ne 'Completed' -or $ps.Streams.Error.Count -ne 0 -or $out.Count -ne 1 -or [string]$out[0] -cne 'INVENTORY_RESOLVER_ISOLATED_PASS'){throw ('Modulo isolado falhou: state='+$ps.InvocationStateInfo.State+'; out='+($out -join '|')+'; errors='+($ps.Streams.Error -join ';'))}
}finally{$ps.Dispose()}
if((Get-FileHash -LiteralPath $module).Hash -cne (Get-FileHash -LiteralPath $copy).Hash){throw 'Modulo alterado durante descoberta'}
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($module,[ref]$tokens,[ref]$errors)
$functions=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Get-ScriptToolInventory'},$false))
if($errors.Count -or $functions.Count -ne 1){throw 'Inventario canonico deve ter uma definicao'}
'INVENTORY_RESOLVER_INTEGRATION_PASS; modulo isolado e diagnostico de todas ausencias; '+$work
