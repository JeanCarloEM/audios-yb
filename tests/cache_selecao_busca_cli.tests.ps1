#requires -Version 7.0
$ErrorActionPreference='Stop'
$fixtureScriptsRoot=$PSScriptRoot
[void][IO.Directory]::CreateDirectory((Join-Path $fixtureScriptsRoot '.runtime-cache-busca'))
$harness=Join-Path $fixtureScriptsRoot 'direto_produtor_aac_cli.tests.ps1'
if((Get-FileHash -LiteralPath $harness).Hash -cne '8B358288CF2E316AF1F3F332505830F2B1E5633B32F90DD28AB437FD43D42545'){throw 'Harness alterado'}
$ht=$null;$he=$null;$ha=[Management.Automation.Language.Parser]::ParseFile($harness,[ref]$ht,[ref]$he)
$loops=@($ha.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.ForEachStatementAst]})
if($he.Count -or $loops.Count -ne 1){throw 'Checkpoint do harness ambiguo'}
$prefix=@($ha.EndBlock.Statements|Where-Object {$_.Extent.EndOffset -le $loops[0].Extent.StartOffset})
foreach($statement in $prefix){
 # Preserva o texto literal de mocks, cujo PSScriptRoot deve ser o case futuro.
 $snippet=$statement.Extent.Text
 if(-not ($statement -is [Management.Automation.Language.AssignmentStatementAst] -and $statement.Left -is [Management.Automation.Language.VariableExpressionAst] -and $statement.Left.VariablePath.UserPath -ceq 'mocks')){$snippet=$snippet.Replace('$PSScriptRoot','$fixtureScriptsRoot')}
 . ([scriptblock]::Create($snippet))
}
# Baseline por extracao deterministica do setup existente.
$inner=@($loops[0].Body.Statements)
if($inner.Count -ne 1 -or $inner[0] -isnot [Management.Automation.Language.ForEachStatementAst]){throw 'Loop interno ambiguo'}
$setupStatements=@($inner[0].Body.Statements)
$stops=@($setupStatements|Where-Object {$_ -is [Management.Automation.Language.PipelineAst] -and $_.PipelineElements.Count -eq 1 -and $_.PipelineElements[0] -is [Management.Automation.Language.CommandAst] -and $_.PipelineElements[0].GetCommandName() -ceq 'Push-Location'})
if($stops.Count -ne 1){throw 'Fim do setup ambiguo'}
$variant='technical';$mode='direto_interativo'
foreach($setupStatement in $setupStatements){
 if($setupStatement.Extent.StartOffset -ge $stops[0].Extent.StartOffset){break}
 . ([scriptblock]::Create($setupStatement.Extent.Text))
 # Metadata musical do mock, sem mudar variante usada para criar aprovacoes.
 if($setupStatement -is [Management.Automation.Language.AssignmentStatementAst] -and $setupStatement.Left -is [Management.Automation.Language.VariableExpressionAst] -and $setupStatement.Left.VariablePath.UserPath -ceq 'config'){$config.variant='legacy_csv'}
}
if(Test-Path -LiteralPath $approvalCsv){throw 'Aprovacao humana indevida no baseline'}
$cliLog=Join-Path $case 'cli.log'
Push-Location $work
try{& $scriptPath -NaoInterativo *> $cliLog;$caseExit=$LASTEXITCODE}finally{Pop-Location}
if($caseExit -ne 0){throw ('Baseline CLI falhou exit='+$caseExit+'; log='+$cliLog)}
$dest=Join-Path $case 'destino';$statePath=Join-Path $dest '.controle/estado.json'
$state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -AsHashtable
$records=@($state.registros.Values);$finals=@(Get-ChildItem -LiteralPath $dest -File -Filter '*.m4a')
$counts=Get-Content -LiteralPath $config.log -Raw|ConvertFrom-Json
if($records.Count -ne 1 -or $finals.Count -ne 1 -or $records[0].resultado -cne 'baixado' -or $records[0].codec -cne 'aac' -or -not $records[0].auditoria.validado -or $state.publicacoes_pendentes.Count -ne 0 -or $counts.reads -ne 0 -or $counts.downloads -ne 1){throw 'Contrato baseline AACv2 nao cumprido'}
foreach($section in @($records[0],$state.videos.TestVideo01,$records[0].auditoria,$state.videos.TestVideo01.auditoria)){if($section.ContainsKey('aprovacao_musical') -or $section.selecao_tecnica.versao -ne 2){throw 'Prova baseline/flags indevidas'}}
if((Get-FileHash -LiteralPath $finals[0].FullName).Hash.ToLowerInvariant() -cne $hash -or (Get-FileHash -LiteralPath $fixture).Hash.ToLowerInvariant() -cne $hash -or (Get-FileHash -LiteralPath $csv).Hash -cne $csvHash){throw 'Fonte/arquivo/CSV alterados'}
$receipt=Join-Path $fixtureScriptsRoot '.runtime-cache-busca/baseline.json'
@{case=$case;state_path=$statePath;final_path=$finals[0].FullName;csv_path=$csv;fixture_path=$fixture;source_sha256=$hash;csv_sha256=$csvHash;main_sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'baixar_audios_ytdlp.ps1')).Hash;script_path=$scriptPath}|ConvertTo-Json|Set-Content -LiteralPath $receipt -Encoding utf8
'CACHE_BASELINE_PASS; '+$receipt
