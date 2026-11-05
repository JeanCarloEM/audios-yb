#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'evidencias_fonte.ps1')
$base=Join-Path $PSScriptRoot ('.runtime-evidencias-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $base 'raiz espaço ação'
$control=Join-Path $root 'destino/.controle'
$isca=Join-Path $base 'cwd'
foreach($p in @($root,$control,$isca,(Join-Path $root 'tests'),(Join-Path $root 'destino'))){[void][IO.Directory]::CreateDirectory($p)}
$fixture='[{"video_id":"TestVideo01","formato_id":"140","sha256":"candidate-only"}]'
$a=Join-Path $root 'manifesto.json'
$b=Join-Path $control 'outro.json'
foreach($p in @($a,$b,(Join-Path $root 'ignorar.exemplo.json'),(Join-Path $isca 'isca.json'),(Join-Path $root 'tests/isca.json'),(Join-Path $root 'destino/isca.json'))){[IO.File]::WriteAllText($p,$fixture)}
[IO.File]::WriteAllText((Join-Path $root 'ferramentas.json'),'{"version":"1"}')
[IO.File]::WriteAllText((Join-Path $control 'estado.json'),'{"registros":{}}')
[IO.File]::WriteAllText((Join-Path $root 'invalido.json'),'{')
$before=@(Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {$_.FullName+'|'+(Get-FileHash -LiteralPath $_.FullName).Hash})
Push-Location $isca
try{
 $found=@(Find-SourceEvidencePaths -Root $root -Control $control -WarningAction SilentlyContinue)
 $expected=@($a,$b|Sort-Object)
 if($found.Count -ne 2 -or @((Compare-Object $expected $found)).Count){throw ('Diretorios errados: '+($found -join ','))}
 $one=@(Find-SourceEvidencePaths -Root $root -Control (Join-Path $base 'ausente') -WarningAction SilentlyContinue)
 if($one.Count -ne 1 -or $one[0] -ne $a){throw 'Control ausente alterou Root'}
 $duplicate=@(Find-SourceEvidencePaths -Root $root -Control $root -WarningAction SilentlyContinue)
 if($duplicate.Count -ne 1 -or $duplicate[0] -ne $a){throw 'Diretorios iguais nao deduplicados'}
 $none=@(Find-SourceEvidencePaths -Root (Join-Path $base 'ausente') -Control (Join-Path $base 'ausente2'))
 if($none.Count){throw 'Inventou candidato ausente'}
}finally{Pop-Location}
$after=@(Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {$_.FullName+'|'+(Get-FileHash -LiteralPath $_.FullName).Hash})
if(@(Compare-Object $before $after).Count){throw 'Descoberta alterou arquivos'}
'EVIDENCIAS_PATHS_PASS: Root/Control, cwd, exemplo, schema, JSON invalido, ausentes, deduplicacao e leitura sem alteracoes'
