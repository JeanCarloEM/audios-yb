#requires -Version 7.0
param([ValidateSet('valid','metadata_mismatch','id_mismatch','ambiguous','missing_evidence')][string]$Scenario='valid')
$ErrorActionPreference='Stop'
$fixtureScriptsRoot=$PSScriptRoot
$repo=Split-Path -Parent $PSScriptRoot
$baseline=Join-Path $PSScriptRoot 'cache_selecao_busca_cli.tests.ps1'
if((Get-FileHash -LiteralPath $baseline).Hash -cne '9275B3C00FA600E0E7F3D852F1EF4C4354259A548D734CC6065D55B225E41C6A'){throw 'Setup baseline alterado'}
$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile($baseline,[ref]$t,[ref]$e)
$stop=@($a.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left -is [Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'cliLog'})
if($e.Count -or $stop.Count -ne 1){throw 'Checkpoint setup ambiguo'}
# Reutiliza preparacao real existente, com URL de busca e sem chamar baseline direto.
$setup=@($a.EndBlock.Statements|Where-Object {$_.Extent.EndOffset -le $stop[0].Extent.StartOffset})
foreach($st in $setup){
 if($st -is [Management.Automation.Language.AssignmentStatementAst] -and $st.Left -is [Management.Automation.Language.VariableExpressionAst] -and $st.Left.VariablePath.UserPath -ceq 'fixtureScriptsRoot'){continue}
 elseif($st -is [Management.Automation.Language.AssignmentStatementAst] -and $st.Left -is [Management.Automation.Language.VariableExpressionAst] -and $st.Left.VariablePath.UserPath -ceq 'mode'){$mode='auto_sem_aprovacao'}
 elseif($st -is [Management.Automation.Language.AssignmentStatementAst] -and $st.Left -is [Management.Automation.Language.VariableExpressionAst] -and $st.Left.VariablePath.UserPath -ceq 'variant'){$variant=if($Scenario -ceq 'missing_evidence'){'missing_evidence'}else{'technical'}}
 else{. ([scriptblock]::Create($st.Extent.Text))}
}
switch($Scenario){
 'metadata_mismatch'{$config.variant='technical'}
 'id_mismatch'{$config.variant='bad_id'}
 'ambiguous'{$config.unique=$false}
}
[IO.File]::WriteAllText((Join-Path $case 'cenario.json'),($config|ConvertTo-Json -Depth 8))
$log=Join-Path $case 'search-cli.log'
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File $scriptPath -NaoInterativo *> $log
if($LASTEXITCODE -ne 0){throw ('CLI busca falhou; '+$log)}
$statePath=Join-Path $case 'destino/.controle/estado.json'
$state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -AsHashtable
$records=@($state.registros.Values)
if($records.Count -ne 1){throw 'Registros divergentes'}
$r=$records[0];$counts=Get-Content -LiteralPath $config.log -Raw|ConvertFrom-Json
$expected=switch($Scenario){valid{'baixado'}missing_evidence{'pendente_qualidade'}default{'pendente_auditoria'}}
$downloads=if($Scenario -in @('valid','missing_evidence')){1}else{0}
if($r.resultado -cne $expected -or $counts.downloads -ne $downloads -or $counts.reads -ne 0){throw ('Busca '+$Scenario+' esperado='+$expected+' efetivo='+$r.resultado+'; '+$r.motivo+'; log='+$log)}
$dest=Join-Path $case 'destino'
$finals=@(Get-ChildItem -LiteralPath $dest -File -Filter '*.m4a')
if($Scenario -ceq 'valid'){
 if($finals.Count -ne 1 -or $r.criterio_selecao -cne 'busca_exata_canal_artista_unica' -or $r.codec -cne 'aac'){throw 'Saida da busca incorreta'}
 foreach($section in @($r,$state.videos.TestVideo01,$r.auditoria,$state.videos.TestVideo01.auditoria)){
  $p=$section.selecao_tecnica
  if($section.ContainsKey('aprovacao_musical') -or $p.versao -ne 3 -or $p.video_id -cne 'TestVideo01' -or $p.criterio -cne 'busca_exata_canal_artista_unica' -or $p.referencia.url_original -cne 'https://www.youtube.com/results?search_query=Artista+Faixa' -or $p.metadados.title -cne 'Artista - Faixa' -or $p.candidatos.Count -ne 1 -or $p.ContainsKey('sem_vocais_conferido')){throw 'Prova v3/flags persistidas invalidas'}
 }
 if($state.publicacoes_pendentes.Count -ne 0 -or (Get-FileHash -LiteralPath $finals[0].FullName).Hash.ToLowerInvariant() -cne $hash){throw 'Journal/hash divergentes'}
 # Mesmo CSV, agora offline: exercita cache v3 real apos producao real.
 $config.offline=$true;$config.remotes=0;$config.downloads=0;$config.reads=0
 [IO.File]::WriteAllText((Join-Path $case 'cenario.json'),($config|ConvertTo-Json -Depth 8))
 & 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File $scriptPath -NaoInterativo *> (Join-Path $case 'search-reuse.log')
 if($LASTEXITCODE -ne 0){throw 'Reexecucao busca falhou'}
 $again=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -AsHashtable
 $counts=Get-Content -LiteralPath $config.log -Raw|ConvertFrom-Json
 if(@($again.registros.Values)[0].resultado -cne 'existente' -or $counts.remotes -ne 0 -or $counts.downloads -ne 0 -or $counts.reads -ne 0 -or (Get-FileHash -LiteralPath $finals[0].FullName).Hash.ToLowerInvariant() -cne $hash){throw 'Reuso offline da busca falhou'}
}else{
 if($finals.Count -ne 0){throw 'Negativo publicou audio'}
 if($Scenario -ceq 'missing_evidence'){
  $kept=Join-Path $dest '.controle/fontes/TestVideo01/256.m4a'
  if($r.selecao_tecnica.versao -ne 3 -or (Get-FileHash -LiteralPath $kept).Hash.ToLowerInvariant() -cne $hash){throw 'Fonte/prova nao preservadas'}
 }
}
if((Get-FileHash -LiteralPath $csv).Hash -cne $csvHash -or (Get-FileHash -LiteralPath $fixture).Hash.ToLowerInvariant() -cne $hash){throw 'CSV/fonte alterados'}
@{scenario=$Scenario;expected=$expected;result=$r.resultado;source_sha256=$hash;main_sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'baixar_audios_ytdlp.ps1')).Hash;case=$case;scope='produtor busca unica novoID, AAC real, IOremota simulada; nao verdade musical/vocal nem novoRowvideoexistente'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $case 'prova-busca-produtora.json') -Encoding utf8
'SEARCH_PRODUCER_PASS '+$Scenario+'; '+$case
