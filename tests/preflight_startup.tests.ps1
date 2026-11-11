#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'baixar_audios_ytdlp.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Sintaxe do principal invalida'}
$tries=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})
if($tries.Count -ne 1){throw 'Try principal ambiguo'}
$statements=@($tries[0].Body.Statements)
$indices=@(for($i=0;$i -lt $statements.Count;$i++){
    $s=$statements[$i]
    if($s -is [Management.Automation.Language.AssignmentStatementAst] -and $s.Left -is [Management.Automation.Language.VariableExpressionAst] -and $s.Left.VariablePath.UserPath -ceq 'tools'){$i}
})
if($indices.Count -ne 1){throw 'Atribuicao tools ambigua'}
$prefix=[scriptblock]::Create(($statements[0..$indices[0]]|ForEach-Object {$_.Extent.Text}) -join "`n")
$tests=(Get-Item -LiteralPath $PSScriptRoot).FullName
$fixture=Join-Path $tests ('.runtime-startup-preflight-'+[guid]::NewGuid().ToString('N'))
if([IO.Path]::GetDirectoryName($fixture) -cne $tests){throw 'Fixture fora de tests'}
if(Test-Path -LiteralPath $fixture){throw 'Fixture ja existe'}
$owned=$false;$script:Checks=0
function Assert($condition,$message){if(!$condition){throw $message};$script:Checks++}
function Resolve-ScriptTools([string]$Root,[switch]$BootstrapYtdlp){
    $script:Calls++
    Assert ($Root -ceq $repo -and $BootstrapYtdlp) 'Parametros do resolver alterados'
    Assert ([IO.Directory]::Exists($script:Out) -and [IO.Directory]::Exists($script:Control)) 'Resolver chamado antes de preparar diretorios'
    Assert (@(Get-ChildItem -LiteralPath $script:Out -File -Force).Count -eq 0 -and @(Get-ChildItem -LiteralPath $script:Control -Force).Count -eq 0) 'Probe deixou residuo antes do resolver'
    return @{}
}
function RunCase([string]$Name){
    $script:Root=$repo;$script:Out=Join-Path $fixture $Name;$script:Control=Join-Path $script:Out '.controle';$script:Calls=0
    $Interativo=($Name -ceq 'conflito');$NaoInterativo=$Interativo
    $blocked=$null
    if($Name -ceq 'outarquivo'){$blocked=$script:Out}
    if($Name -ceq 'controlearquivo'){[void][IO.Directory]::CreateDirectory($script:Out);$blocked=$script:Control}
    if($blocked){[IO.File]::WriteAllBytes($blocked,[byte[]](11,22,33))}
    $problem=$null
    try{& $prefix}catch{$problem=$_}
    if($Name -ceq 'positivo'){
        Assert ($null -eq $problem) ('Falha no startup positivo: '+$problem)
        Assert ($script:Calls -eq 1) 'Resolver deve ser chamado uma vez'
    }else{
        Assert ($null -ne $problem) 'Startup deveria falhar'
        Assert ($script:Calls -eq 0) 'Bootstrap chamado apesar do erro de entrada'
        if($Name -ceq 'conflito'){
            Assert ($problem.Exception.Message -ceq 'Use apenas um modo: Interativo ou NaoInterativo') 'Falha de modo nao causal'
            Assert (!(Test-Path -LiteralPath $script:Out)) 'Conflito criou diretorio'
        }else{
            $exception=$problem.Exception
            while($null -ne $exception -and $exception -isnot [IO.IOException]){$exception=$exception.InnerException}
            Assert ($exception -is [IO.IOException]) 'Erro nao corresponde ao bloqueio de IO'
            Assert ([Convert]::ToHexString([IO.File]::ReadAllBytes($blocked)) -ceq '0B1621') 'Arquivo estrangeiro alterado'
        }
    }
}
try{
    [void][IO.Directory]::CreateDirectory($fixture);$owned=$true
    foreach($case in @('positivo','outarquivo','controlearquivo','conflito')){RunCase $case}
}finally{if($owned){[IO.Directory]::Delete($fixture,$true)}}
Write-Output "STARTUP_PREFLIGHT_PASS checks$script:Checks; prefixo real/IO real/resolver simulado/sem rede"
