#requires -Version 7.0
param([ValidateSet('valid','bad_proof','wrong_profile','bad_final_hash','missing_document')][string]$Scenario='valid')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot;$fixtureScriptsRoot=$PSScriptRoot
$producer=Join-Path $PSScriptRoot 'busca_produtor_aac_cli.tests.ps1'
if((Get-FileHash -LiteralPath $producer).Hash -cne 'C248CB0A3741A27972D6B083C9ACE28A7A34DFB47513376DBAC007611DBBAC36'){throw 'Setup produtor alterado'}
$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile($producer,[ref]$t,[ref]$e)
$stop=@($a.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left -is [Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq 'log'})
if($e.Count -or $stop.Count -ne 1){throw 'Checkpoint produtor ambiguo'}
$preparation=@($a.EndBlock.Statements|Where-Object {$_.Extent.EndOffset -le $stop[0].Extent.StartOffset})
foreach($setupPart in $preparation){
 if($setupPart -is [Management.Automation.Language.AssignmentStatementAst] -and $setupPart.Left -is [Management.Automation.Language.VariableExpressionAst] -and $setupPart.Left.VariablePath.UserPath -ceq 'fixtureScriptsRoot'){continue}
 $snippet=$setupPart.Extent.Text
 if($setupPart -is [Management.Automation.Language.AssignmentStatementAst] -and $setupPart.Left -is [Management.Automation.Language.VariableExpressionAst] -and $setupPart.Left.VariablePath.UserPath -cin @('repo','baseline')){$snippet=$snippet.Replace('$PSScriptRoot','$fixtureScriptsRoot')}
 . ([scriptblock]::Create($snippet))
}
# Retira somente mock de busca de alto nivel. Cache e Candidate-Score sao REAIS.
$ma=[Management.Automation.Language.Parser]::ParseInput($mocks,[ref]$t,[ref]$e)
$search=@($ma.FindAll({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -ceq 'Search-Candidates'},$false))
if($e.Count -or $search.Count -ne 1){throw 'Mock busca ambiguo'}
$mocks=$mocks.Remove($search[0].Extent.StartOffset,$search[0].Extent.Text.Length)
$ma=[Management.Automation.Language.Parser]::ParseInput($mocks,[ref]$t,[ref]$e)
$invoke=@($ma.FindAll({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -ceq 'Invoke-Checked'},$false))
if($e.Count -or $invoke.Count -ne 1){throw 'Transporte ambiguo'}
$searchIO=@'
    if($Arguments -contains '--flat-playlist'){
        if($script:E2E.offline){$script:E2E.remotes++;Save-E2E;throw 'Busca remota proibida na segunda linha'}
        $script:E2E.searches++;Save-E2E
        $entries=@(@{id='TestVideo01';title='Artista - Faixa';channel='Artista - Topic';uploader='Artista';duration=4})
        return @{code=0;tentativas=1;out=(@{entries=$entries}|ConvertTo-Json -Depth 8);err='';timeout=$false}
    }
'@
$mocks=$mocks.Insert($invoke[0].Body.Extent.StartOffset+1,[Environment]::NewLine+$searchIO+[Environment]::NewLine)
$source=[IO.File]::ReadAllText((Join-Path $repo 'baixar_audios_ytdlp.ps1'))
$a=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
$mainTry=@($a.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})
if($e.Count -or $mainTry.Count -ne 1){throw 'Main ambiguo'}
[IO.File]::WriteAllText($scriptPath,$source.Insert($mainTry[0].Extent.StartOffset,$mocks+[Environment]::NewLine),[Text.UTF8Encoding]::new($true))
$config.searches=0
[IO.File]::WriteAllText((Join-Path $case 'cenario.json'),($config|ConvertTo-Json -Depth 8))
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File $scriptPath -NaoInterativo *> (Join-Path $case 'first.log')
if($LASTEXITCODE -ne 0){throw ('Primeira busca falhou; '+$case)}
$statePath=Join-Path $case 'destino/.controle/estado.json'
$state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -AsHashtable
$old=@($state.registros.Values)[0];$oldKey=$old.chave
$counts=Get-Content -LiteralPath $config.log -Raw|ConvertFrom-Json
if($old.resultado -cne 'baixado' -or $counts.searches -ne 1 -or $counts.downloads -ne 1 -or $counts.reads -ne 0 -or $state.buscas.Count -ne 1){throw 'Primeira busca nao publicou/cacheou'}
$oldFields=@{};foreach($k in @('chave','ordem','url_original','video_id','arquivo','resultado')){$oldFields[$k]=$old[$k]}
$final=Join-Path (Join-Path $case 'destino') $old.arquivo
if((Get-FileHash -LiteralPath $final).Hash.ToLowerInvariant() -cne $hash){throw 'Hash inicial divergente'}
$rows=@(Import-Csv -LiteralPath $csv);$rows[0].Ordem='2'
$rows|Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8
$csvHash=(Get-FileHash -LiteralPath $csv).Hash
$keyText=[string]::Join([char]31,@('2','Artista','Faixa','https://www.youtube.com/results?search_query=Artista+Faixa'))
$newKey=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($keyText))).ToLowerInvariant()
$expected='existente'
switch($Scenario){
 'bad_proof'{$state.videos.TestVideo01.selecao_tecnica.referencia.consulta='forjada';$expected='pendente_auditoria'}
 'wrong_profile'{$state.videos.TestVideo01.selecao_tecnica=@{versao=2;tipo='selecao_tecnica';video_id='TestVideo01';criterio='url_direta_id_literal';metadados=@{id='TestVideo01';title='Artista - Faixa'};referencia=@{artista='Artista';musica='Faixa'}};$expected='pendente_auditoria'}
 'bad_final_hash'{$state.videos.TestVideo01.sha256=('0'*64);$expected='pendente_qualidade'}
 'missing_document'{Remove-Item -LiteralPath (Join-Path $case 'origem.txt');$expected='pendente_qualidade'}
}
[IO.File]::WriteAllText($statePath,($state|ConvertTo-Json -Depth 30),[Text.UTF8Encoding]::new($false))
$config.offline=$true;$config.searches=0;$config.remotes=0;$config.downloads=0;$config.reads=0
[IO.File]::WriteAllText((Join-Path $case 'cenario.json'),($config|ConvertTo-Json -Depth 8))
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File $scriptPath -NaoInterativo *> (Join-Path $case 'second.log')
if($LASTEXITCODE -ne 0){throw ('Segunda linha falhou; '+$case)}
$disk=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json -AsHashtable
$counts=Get-Content -LiteralPath $config.log -Raw|ConvertFrom-Json
$r=$disk.registros[$newKey]
if($disk.registros.Count -ne 2 -or $r.resultado -cne $expected -or $counts.searches -ne 0 -or $counts.remotes -ne 0 -or $counts.downloads -ne 0 -or $counts.reads -ne 0){throw ('Nova linha '+$Scenario+' esperado='+$expected+' efetivo='+$r.resultado+'; '+$r.motivo+'; '+$case)}
foreach($k in $oldFields.Keys){if(-not [string]::Equals([string]$disk.registros[$oldKey][$k],[string]$oldFields[$k],[StringComparison]::Ordinal)){throw 'Historico anterior alterado'}}
if($Scenario -ceq 'valid'){
 foreach($section in @($r,$disk.videos.TestVideo01,$r.auditoria,$disk.videos.TestVideo01.auditoria)){if($section.ContainsKey('aprovacao_musical') -or $section.selecao_tecnica.versao -ne 3 -or $section.selecao_tecnica.ContainsKey('sem_vocais_conferido')){throw 'Contrato v3 perdido'}}
 if($r.arquivo -cne $old.arquivo -or $r.criterio_selecao -cne 'busca_exata_canal_artista_unica' -or $r.titulo_video -cne 'Artista - Faixa'){throw 'Nome/titulo/criterio nao preservados'}
}
if((Get-FileHash -LiteralPath $final).Hash.ToLowerInvariant() -cne $hash -or (Get-FileHash -LiteralPath $fixture).Hash.ToLowerInvariant() -cne $hash -or (Get-FileHash -LiteralPath $csv).Hash -cne $csvHash){throw 'Arquivo/fonte/CSV alterados'}
@{scenario=$Scenario;result=$r.resultado;expected=$expected;source_sha256=$hash;main_sha256=(Get-FileHash -LiteralPath (Join-Path $repo 'baixar_audios_ytdlp.ps1')).Hash;case=$case;scope='nova linha busca com cache real/IOsimulada; nenhum novo download/pergunta';records=$disk.registros.Count}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $case 'prova-reuso-busca.json') -Encoding utf8
'SEARCH_NEW_ROW_REUSE_PASS '+$Scenario+'; '+$case
