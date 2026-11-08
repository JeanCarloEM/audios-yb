#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1.0
$repo=Split-Path -Parent $PSScriptRoot
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'baixar_audios_ytdlp.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Sintaxe invalida'}
$defs=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Save-State'},$true))
if($defs.Count -ne 1){throw 'Save-State ambiguo'}
. ([scriptblock]::Create($defs[0].Extent.Text))
$script:Control=Join-Path $PSScriptRoot ('.runtime-estado-duravel-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $script:Control
$script:StateFile=Join-Path $script:Control 'estado.json'
$script:Utf8=[Text.UTF8Encoding]::new($false)
$music='Faixa colet'+[char]0x00E2+'nea'
$script:State=@{versao=1;registros=@{id=@{musica=$music;url_original='https://example.invalid/fixture?x=1&y=2'}};videos=@{};buscas=@{}}
Save-State
$read=ConvertFrom-Json ([IO.File]::ReadAllText($script:StateFile))
if($read.versao -ne 1 -or -not [string]::Equals([string]$read.registros.id.musica,$music,[StringComparison]::Ordinal) -or $read.registros.id.url_original -cne 'https://example.invalid/fixture?x=1&y=2'){throw 'Primeira gravacao perdeu dados'}
$bytes=[IO.File]::ReadAllBytes($script:StateFile)
if($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191){throw 'BOM inesperado'}
$firstHash=(Get-FileHash -LiteralPath $script:StateFile).Hash
$script:State.videos.id=@{tamanho=42;validado=$true;campo_nulo=$null}
Save-State
$read=ConvertFrom-Json ([IO.File]::ReadAllText($script:StateFile))
if($read.videos.id.tamanho -ne 42 -or $read.videos.id.validado -ne $true -or $null -ne $read.videos.id.campo_nulo -or -not [string]::Equals([string]$read.registros.id.musica,$music,[StringComparison]::Ordinal)){throw 'Substituicao perdeu tipos ou dados'}
$baseline=(Get-FileHash -LiteralPath $script:StateFile).Hash
if($baseline -ceq $firstHash){throw 'Estado nao foi substituido'}
$goodState=$script:State
$deep=@{value='fim'}
for($i=0;$i -lt 30;$i++){$deep=@{child=$deep}}
$script:State=@{deep=$deep}
$caught=$false
try{Save-State}catch{if($_.Exception.Message -notmatch 'JSON'){throw};$caught=$true}
if(-not $caught -or (Get-FileHash -LiteralPath $script:StateFile).Hash -cne $baseline){throw 'Serializacao truncada substituiu estado valido'}
if(@(Get-ChildItem -LiteralPath $script:Control -Filter '.estado.*.tmp' -File).Count -ne 0){throw 'Falha de serializacao criou temporario'}
$script:State=$goodState
$canary=Join-Path $script:Control '.estado.reserva.bak'
[IO.File]::WriteAllText($canary,'backup anterior preservado',$script:Utf8)
$canaryHash=(Get-FileHash -LiteralPath $canary).Hash
if($IsWindows){
 $lock=[IO.File]::Open($script:StateFile,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
 $caught=$false
 try{
  try{Save-State}catch{
   $failure=$_.Exception
   while($null -ne $failure.InnerException){$failure=$failure.InnerException}
   if($failure -isnot [IO.IOException]){throw}
   $caught=$true
  }
 }finally{$lock.Dispose()}
 if(-not $caught -or (Get-FileHash -LiteralPath $script:StateFile).Hash -cne $baseline){throw 'Substituicao bloqueada perdeu estado'}
 if(@(Get-ChildItem -LiteralPath $script:Control -Filter '.estado.*.tmp' -File).Count -ne 0){throw 'Temporario proprio nao foi limpo'}
}else{Write-Output 'ESTADO_LOCK_NEGATIVO_NAO_TESTADO_NESTE_SO'}
if((Get-FileHash -LiteralPath $canary).Hash -cne $canaryHash){throw 'Backup alheio removido'}
Save-State
$read=ConvertFrom-Json ([IO.File]::ReadAllText($script:StateFile))
if($read.videos.id.tamanho -ne 42 -or (Get-FileHash -LiteralPath $canary).Hash -cne $canaryHash){throw 'Recuperacao apos falha perdeu dados'}

# Injetar somente a entropia de nomes na funcao real: CreateNew/IO/limpeza permanecem reais.
$collisionSource=$defs[0].Extent.Text
$entropy="[guid]::NewGuid().ToString('N')"
if(($collisionSource.Split($entropy,[StringSplitOptions]::None).Count-1) -ne 2){throw 'Contrato de entropia mudou'}
$collisionSource=$collisionSource.Replace('function Save-State {','function Save-StateCollision {').Replace($entropy,"'collision-fixture'")
. ([scriptblock]::Create($collisionSource))
$foreignTmp=Join-Path $script:Control '.estado.collision-fixture.tmp'
[IO.File]::WriteAllText($foreignTmp,'temporario preexistente; nao pertence a esta gravacao',$script:Utf8)
$foreignHash=(Get-FileHash -LiteralPath $foreignTmp).Hash
$stateHash=(Get-FileHash -LiteralPath $script:StateFile).Hash
$caught=$false
try{Save-StateCollision}catch{
 $failure=$_.Exception
 while($null -ne $failure.InnerException){$failure=$failure.InnerException}
 if($failure -isnot [IO.IOException]){throw}
 $caught=$true
}
if(-not $caught){throw 'Colisao nao recusada por CreateNew'}
if(-not [IO.File]::Exists($foreignTmp) -or (Get-FileHash -LiteralPath $foreignTmp).Hash -cne $foreignHash -or (Get-FileHash -LiteralPath $script:StateFile).Hash -cne $stateHash){throw 'Colisao apagou temporario alheio ou alterou estado'}
Save-State
if((Get-FileHash -LiteralPath $foreignTmp).Hash -cne $foreignHash){throw 'Gravacao seguinte apagou temporario alheio'}
Write-Output 'ESTADO_COLISAO_TEMPORARIO_ALHEIO_PASS'

Write-Output 'ESTADO_DURAVEL_PASS'
