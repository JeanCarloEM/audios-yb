#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'acesso_diretorio.ps1')
$tests=(Get-Item -LiteralPath (Join-Path $repo 'tests')).FullName
$fixture=Join-Path $tests ('.runtime-directory-probe-check-'+[guid]::NewGuid().ToString('N'))
if([IO.Path]::GetDirectoryName($fixture) -cne $tests){throw 'Fixture fora de tests'}
[void][IO.Directory]::CreateDirectory($fixture)
$checks=0
function Assert($condition,$message){if(!$condition){throw $message};$script:checks++}
function MustFail([scriptblock]$action){$failed=$false;try{& $action | Out-Null}catch{$failed=$true};Assert $failed 'Esperava falha'}
try {
    $foreign=Join-Path $fixture 'preservar.bin'
    [IO.File]::WriteAllBytes($foreign,[byte[]](1,3,5,7))
    $r=Invoke-DirectoryWriteProbe -Root $fixture
    Assert ($r -is [hashtable]) 'Retorno deve ser hashtable unico'
    Assert ($r.directory -ceq $fixture) 'Diretorio absoluto incorreto'
    Assert ($r.create_write_delete_verified -is [bool] -and $r.create_write_delete_verified) 'Ciclo nao confirmado'
    Assert (@(Get-ChildItem -LiteralPath $fixture -Force).Count -eq 1) 'Temporario residual'
    $literal=Join-Path $fixture '[literal]'
    [void][IO.Directory]::CreateDirectory($literal)
    Push-Location -LiteralPath $fixture
    try {$r=Invoke-DirectoryWriteProbe -Root './[literal]'}finally{Pop-Location}
    Assert ($r.directory -ceq $literal) 'Root relativo literal incorreto'
    Assert (@(Get-ChildItem -LiteralPath $literal -Force).Count -eq 0) 'Literal nao limpo'
    $missing=Join-Path $fixture 'nao-criar'
    MustFail {Invoke-DirectoryWriteProbe -Root $missing}
    Assert (!(Test-Path -LiteralPath $missing)) 'Criou Root ausente'
    MustFail {Invoke-DirectoryWriteProbe -Root $foreign}
    # Substitui apenas entropia; a abertura e a colisao permanecem IO reais.
    function New-DirectoryWriteProbeName { 'preservar.bin' }
    MustFail {Invoke-DirectoryWriteProbe -Root $fixture}
    Assert ([Convert]::ToHexString([IO.File]::ReadAllBytes($foreign)) -ceq '01030507') 'Colisao alterou arquivo estrangeiro'
    Assert (@(Get-ChildItem -LiteralPath $fixture -File -Force).Count -eq 1) 'Colisao criou arquivo extra'
    Write-Output "DIRECTORY_WRITE_PROBE_PASS checks$checks"
}
finally {Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction Stop}
