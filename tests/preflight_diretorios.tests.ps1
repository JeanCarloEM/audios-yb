#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'preflight_diretorios.ps1')
$tests=(Get-Item -LiteralPath $PSScriptRoot).FullName
$root=Join-Path $tests ('.runtime-output-preflight-'+[guid]::NewGuid().ToString('N'))
if([IO.Path]::GetDirectoryName($root) -cne $tests){throw 'Fixture fora de tests'}
if(Test-Path -LiteralPath $root){throw 'Fixture ja existe'}
$owned=$false
$checks=0
function Assert($condition,$message){if(!$condition){throw $message};$script:checks++}
function ExpectIOException([scriptblock]$Action){
    $problem=$null
    try{& $Action | Out-Null}catch{$problem=$_}
    Assert ($null -ne $problem) 'Esperava erro de IO'
    $exception=$problem.Exception
    while($null -ne $exception -and $exception -isnot [IO.IOException]){$exception=$exception.InnerException}
    Assert ($exception -is [IO.IOException]) 'Erro nao corresponde a IOException'
}
function CheckLayout($result,[string]$out){
    $control=Join-Path $out '.controle'
    Assert ($result -is [hashtable]) 'Retorno deve ser hashtable'
    Assert ($result.Count -eq 2 -and $result.ContainsKey('Out') -and $result.ContainsKey('Control')) 'Chaves incorretas'
    Assert ($result.Out -ceq $out -and $result.Control -ceq $control) 'Paths divergiram do contrato'
    Assert ([IO.Directory]::Exists($out) -and [IO.Directory]::Exists($control)) 'Pastas ausentes'
}
try{
    [void][IO.Directory]::CreateDirectory($root);$owned=$true
    $out=Join-Path $root 'novo'
    $control=Join-Path $out '.controle'
    CheckLayout (Initialize-OutputWriteAccess -Out $out) $out
    Assert (@(Get-ChildItem -LiteralPath $out -File -Force).Count -eq 0) 'Residuo em Out'
    Assert (@(Get-ChildItem -LiteralPath $control -Force).Count -eq 0) 'Residuo em Control'
    $a=Join-Path $out 'a.bin';$b=Join-Path $control 'b.bin'
    [IO.File]::WriteAllBytes($a,[byte[]](1,3,5));[IO.File]::WriteAllBytes($b,[byte[]](2,4,6))
    CheckLayout (Initialize-OutputWriteAccess -Out $out) $out
    Assert ([Convert]::ToHexString([IO.File]::ReadAllBytes($a)) -ceq '010305') 'Sentinela Out alterada'
    Assert ([Convert]::ToHexString([IO.File]::ReadAllBytes($b)) -ceq '020406') 'Sentinela Control alterada'
    Assert (@(Get-ChildItem -LiteralPath $out -File -Force).Count -eq 1 -and @(Get-ChildItem -LiteralPath $control -Force).Count -eq 1) 'Arquivo adicional apos reuso'
    $literal=Join-Path $root '[literal]'
    CheckLayout (Initialize-OutputWriteAccess -Out $literal) $literal
    Assert (@(Get-ChildItem -LiteralPath $literal -File -Force).Count -eq 0 -and @(Get-ChildItem -LiteralPath (Join-Path $literal '.controle') -Force).Count -eq 0) 'Residuo em caminho literal'
    $blocked=Join-Path $root 'bloqueado';[void][IO.Directory]::CreateDirectory($blocked)
    $blockFile=Join-Path $blocked '.controle';[IO.File]::WriteAllBytes($blockFile,[byte[]](7,8,9))
    ExpectIOException {Initialize-OutputWriteAccess -Out $blocked}
    Assert ([Convert]::ToHexString([IO.File]::ReadAllBytes($blockFile)) -ceq '070809') 'Controle arquivo alterado'
    $outFile=Join-Path $root 'saida.bin';[IO.File]::WriteAllBytes($outFile,[byte[]](10,11,12))
    ExpectIOException {Initialize-OutputWriteAccess -Out $outFile}
    Assert ([Convert]::ToHexString([IO.File]::ReadAllBytes($outFile)) -ceq '0A0B0C') 'Out arquivo alterado'
    Push-Location -LiteralPath $root
    try{
        $problem=$null
        try{Initialize-OutputWriteAccess -Out 'relativo' | Out-Null}catch{$problem=$_}
        Assert ($null -ne $problem) 'Caminho relativo aceito'
        Assert (!(Test-Path -LiteralPath (Join-Path $root 'relativo'))) 'Caminho relativo criado'
    }finally{Pop-Location}
    Write-Output "OUTPUT_PREFLIGHT_PASS checks$checks"
}finally{if($owned){Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop}}
