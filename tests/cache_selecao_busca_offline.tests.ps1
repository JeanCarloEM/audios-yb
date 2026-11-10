#requires -Version 7.0
param([ValidateSet('valid','video_query','record_query','mixed_kind','bad_final_hash','missing_document','record_url')][string]$Scenario='valid')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
[void][IO.Directory]::CreateDirectory((Join-Path $PSScriptRoot '.runtime-cache-busca'))
$receipt=Join-Path $PSScriptRoot '.runtime-cache-busca/baseline.json'
if(-not (Test-Path -LiteralPath $receipt)){
 $log=Join-Path $PSScriptRoot '.runtime-cache-busca/baseline-setup.log'
 & 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File (Join-Path $PSScriptRoot 'cache_selecao_busca_cli.tests.ps1') *> $log
 if($LASTEXITCODE -ne 0){throw ('Baseline indisponivel; '+$log)}
}
$b=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json -AsHashtable
if((Get-FileHash -LiteralPath $b.final_path).Hash.ToLowerInvariant() -cne $b.source_sha256 -or (Get-FileHash -LiteralPath $b.fixture_path).Hash.ToLowerInvariant() -cne $b.source_sha256 -or (Get-FileHash -LiteralPath $b.csv_path).Hash -cne $b.csv_sha256){throw 'Baseline divergiu'}
$case=Join-Path $PSScriptRoot ('.runtime-cache-search-'+[guid]::NewGuid().ToString('N'))
if(Test-Path -LiteralPath $case){throw 'Case ja existe'}
Copy-Item -LiteralPath $b.case -Destination $case -Recurse
$statePath=Join-Path $case 'destino/.controle/estado.json';$csv=Join-Path $case 'faixas.csv'
if(-not (Test-Path -LiteralPath $statePath)){throw 'Clone invalido'}
# Recria somente script de transporte sobre main ATUAL; validadores/produto reais.
$harness=Join-Path $PSScriptRoot 'direto_produtor_aac_cli.tests.ps1'
if((Get-FileHash -LiteralPath $harness).Hash -cne '8B358288CF2E316AF1F3F332505830F2B1E5633B32F90DD28AB437FD43D42545'){throw 'Harness alterado'}
$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile($harness,[ref]$t,[ref]$e)
$assignment=@($a.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left -is [Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'mocks'})
if($e.Count -or $assignment.Count -ne 1){throw 'Transporte ambiguo'}
. ([scriptblock]::Create($assignment[0].Extent.Text))
$source=[IO.File]::ReadAllText((Join-Path $repo 'baixar_audios_ytdlp.ps1'))
$a=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
$mainTry=@($a.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})
if($e.Count -or $mainTry.Count -ne 1){throw 'Main invalido'}
$scriptPath=Join-Path $case 'baixar_audios_ytdlp.ps1'
[IO.File]::WriteAllText($scriptPath,$source.Insert($mainTry[0].Extent.StartOffset,$mocks+[Environment]::NewLine),[Text.UTF8Encoding]::new($true))
$searchUrl='https://www.youtube.com/results?search_query=Artista+Faixa'
$rows=@(Import-Csv -LiteralPath $csv)
if($rows.Count -ne 1){throw 'CSV ambiguo'}
$rows[0].Link_YouTube=$searchUrl;$rows[0].Tipo_link='Busca'
$rows|Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
$csvHash=(Get-FileHash -LiteralPath $csv).Hash
$state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -AsHashtable
$rec=@($state.registros.Values)[0]
$directProof=$state.videos.TestVideo01.selecao_tecnica
if($rec.selecao_tecnica.metadados.title -cne 'Artista - Faixa'){throw 'Metadata baseline diverge da fixture literal'}
# Prova literal independente, consistente com metadata do transporte controlado.
$proof=@{versao=[int]3;tipo='selecao_tecnica';video_id='TestVideo01';criterio='busca_exata_canal_artista_unica';metadados=@{id='TestVideo01';title='Artista - Faixa';channel='Artista - Topic'};referencia=@{artista='Artista';musica='Faixa';url_original=$searchUrl;consulta='Artista Faixa'};candidatos=@(@{id='TestVideo01';titulo='Artista - Faixa';canal='Artista - Topic'})}
$keyText=[string]::Join([char]31,@('1','Artista','Faixa',$searchUrl))
$key=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($keyText))).ToLowerInvariant()
$rec.chave=$key;$rec.url_original=$searchUrl;$rec.tipo_link='Busca';$rec.criterio_selecao=$proof.criterio
foreach($section in @($rec,$state.videos.TestVideo01,$rec.auditoria,$state.videos.TestVideo01.auditoria)){$section.Remove('aprovacao_musical');$section.selecao_tecnica=$proof}
$state.registros=@{};$state.registros[$key]=$rec
$state=$state|ConvertTo-Json -Depth 30|ConvertFrom-Json -AsHashtable
$options=@{};$expected='existente'
switch($Scenario){
 'video_query'{
  $state.videos.TestVideo01.selecao_tecnica.referencia.consulta='forjada';$expected='pendente_auditoria'
  $human=@{versao=1;video_id='TestVideo01';artista='Artista';musica='Faixa';artista_musica_conferidos=$true;versao_conferida=$true;sem_vocais_conferido=$true;origem='arquivo_aprovacoes'}
  $state.videos.TestVideo01.aprovacao_musical=$human;$state.registros[$key].aprovacao_musical=$human
  $approvalPath=Join-Path $case 'aprovacoes-negativo.csv'
  [pscustomobject]@{Ordem='1';VideoId='TestVideo01';ArtistaMusicaConferidos='SIM';VersaoConferida='SIM';SemVocaisConferido='SIM'}|Export-Csv -LiteralPath $approvalPath -NoTypeInformation -Encoding UTF8
  $options.AprovacoesCsv=$approvalPath
 }
 'record_query'{$state.registros[$key].selecao_tecnica.referencia.consulta='forjada';$expected='pendente_auditoria'}
 'mixed_kind'{$state.videos.TestVideo01.selecao_tecnica=$directProof;$expected='pendente_auditoria'}
 'bad_final_hash'{$state.videos.TestVideo01.sha256=('0'*64);$expected='pendente_qualidade'}
 'missing_document'{Remove-Item -LiteralPath (Join-Path $case 'origem.txt');$expected='pendente_qualidade'}
 'record_url'{
  $otherUrl='https://www.youtube.com/results?search_query=Artista%20Faixa'
  $state.registros[$key].url_original=$otherUrl
  $state.registros[$key].selecao_tecnica.referencia.url_original=$otherUrl
  $state.videos.TestVideo01.selecao_tecnica.referencia.url_original=$otherUrl
  $expected='pendente_auditoria'
 }
}
[IO.File]::WriteAllText($statePath,($state|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
$config=Get-Content -LiteralPath (Join-Path $case 'cenario.json') -Raw|ConvertFrom-Json -AsHashtable
$config.offline=$true;$config.downloads=0;$config.remotes=0;$config.reads=0;$config.log=Join-Path $case 'contadores.json'
[IO.File]::WriteAllText((Join-Path $case 'cenario.json'),($config|ConvertTo-Json -Depth 8))
$log=Join-Path $case 'cache-cli.log'
# Processo CLI possui exit code proprio.
$cliArgs=@('-NoProfile','-File',$scriptPath,'-NaoInterativo')
if($options.ContainsKey('AprovacoesCsv')){$cliArgs+=@('-AprovacoesCsv',[string]$options.AprovacoesCsv)}
& 'C:\Program Files\PowerShell\7\pwsh.exe' @cliArgs *> $log
if($LASTEXITCODE -ne 0){throw ('CLI cache falhou; '+$log)}
$disk=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -AsHashtable
$r=$disk.registros[$key];$counts=Get-Content -LiteralPath $config.log -Raw|ConvertFrom-Json
if($r.resultado -cne $expected -or $counts.remotes -ne 0 -or $counts.downloads -ne 0 -or $counts.reads -ne 0){throw ('Cache v3 '+$Scenario+' esperado='+$expected+' efetivo='+$r.resultado+'; '+$r.motivo+'; log='+$log)}
if($Scenario -ceq 'valid'){
 foreach($section in @($r,$disk.videos.TestVideo01,$r.auditoria,$disk.videos.TestVideo01.auditoria)){if($section.ContainsKey('aprovacao_musical') -or $section.selecao_tecnica.versao -ne 3 -or $section.selecao_tecnica.referencia.url_original -cne $searchUrl -or $section.selecao_tecnica.ContainsKey('sem_vocais_conferido')){throw 'Contrato persistido v3 invalido'}}
}
$final=Join-Path (Join-Path $case 'destino') $r.arquivo
if((Get-FileHash -LiteralPath $final).Hash.ToLowerInvariant() -cne $b.source_sha256 -or (Get-FileHash -LiteralPath $csv).Hash -cne $csvHash -or (Get-FileHash -LiteralPath $b.final_path).Hash.ToLowerInvariant() -cne $b.source_sha256 -or (Get-FileHash -LiteralPath $b.csv_path).Hash -cne $b.csv_sha256){throw 'Arquivo/CSV/baseline alterados'}
@{scenario=$Scenario;expected=$expected;result=$r.resultado;main_sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'baixar_audios_ytdlp.ps1')).Hash;baseline_main_sha256=$b.main_sha256;case=$case;source_sha256=$b.source_sha256;scope='cache mesmo registro v3 offline; fixture sem transporte remoto real; nao produtor busca'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $case 'prova-cache.json') -Encoding utf8
'CACHE_SEARCH_OFFLINE_PASS '+$Scenario+'; '+$case
