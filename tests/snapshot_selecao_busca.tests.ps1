#requires -Version 7.0
$ErrorActionPreference='Stop'
# Harness de sentinelas: sem audio real, transporte ou publicacao.
. (Join-Path $PSScriptRoot 'intencao_publicacao.tests.ps1')
foreach($file in @('consulta_busca.ps1','selecao_automatica.ps1','selecao_busca.ps1','selecao_tecnica.ps1','execucao_unica.ps1')){. (Join-Path $repo $file)}
$fixture=Join-Path $PSScriptRoot 'selecao_busca_releitura.tests.ps1'
if((Get-FileHash $fixture).Hash -cne '5796DA1850C2357B6722BDEAAA6B53D4990FF618E967F97300153AE722EFCD08'){throw 'Origem fixture alterada'}
$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile($fixture,[ref]$t,[ref]$e)
foreach($name in @('id','url','literal')){
 $x=@($a.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left -is [Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq $name})
 if($e.Count -or $x.Count -ne 1){throw 'Fixture ambigua'}
 . ([scriptblock]::Create($x[0].Extent.Text))
}
$a=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'selecao_busca_construtor.tests.ps1'),[ref]$t,[ref]$e)
$helper=@($a.FindAll({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -ceq 'Assert-Literal'},$false))
if($e.Count -or $helper.Count -ne 1){throw 'Assercao ausente'}
. ([scriptblock]::Create($helper[0].Extent.Text))
function Set-Key($r){
 $text=[string]::Join([char]31,@($r.ordem.Trim(),$r.artista.Trim(),$r.musica.Trim(),$r.url_original.Trim()))
 $r.chave=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($text))).ToLowerInvariant()
}
$r=$record.Clone();$r.Remove('aprovacao_musical')
$r.artista='Artista';$r.musica='Faixa';$r.video_id=$id;$r.url_original=$url;$r.selecao_tecnica=$literal;Set-Key $r
$params=$base.Clone();$params.VideoId=$id;$params.Record=$r
$before=$r|ConvertTo-Json -Depth 20 -Compress
$snapshot=New-PublicationIntentSnapshot @params
$normalized=Resolve-PublicationSelectionProof -VideoId $id -Artist Artista -Song Faixa -SourceUrl $url -Record $snapshot.registro
if($null -eq $normalized -or $normalized.Kind -cne 'technical_v3'){throw 'Snapshot perdeu v3'}
Assert-Literal $normalized.Proof $literal
if($snapshot.registro.ContainsKey('aprovacao_musical') -or ($r|ConvertTo-Json -Depth 20 -Compress) -cne $before){throw 'Snapshot fabricou legado/mutou entrada'}
$snapshot.registro.selecao_tecnica.referencia.artista='mutado'
if($literal.referencia.artista -cne 'Artista'){throw 'Alias da prova'}
$n=2
$legacy=Resolve-MusicalApprovalProof -VideoId $id -Artist Artista -Song Faixa -RawApproval @{VideoId=$id;ArtistaMusicaConferidos='SIM';VersaoConferida='SIM';SemVocaisConferido='SIM'}
if($null -eq $legacy){throw 'Fixture legado invalida'}
foreach($mut in @(
 {param($r)$r.selecao_tecnica.referencia.consulta='forjada'},
 {param($r)$r.selecao_tecnica.metadados.id='OtherId0123'},
 {param($r)$r.selecao_tecnica.versao='3'},
 {param($r)$r.url_original='https://www.youtube.com/results?search_query=Artista%20Faixa';Set-Key $r}
)){
 $bad=$r|ConvertTo-Json -Depth 20|ConvertFrom-Json -AsHashtable
 $bad.aprovacao_musical=$legacy
 &$mut $bad
 $params.Record=$bad;$caught=$false
 try{$null=New-PublicationIntentSnapshot @params}catch [ArgumentException]{$caught=$true}
 if(-not $caught){throw 'Snapshot aceitou v3 invalida/fallback/contexto da propria prova'};$n++
}
if((Get-FileHash -LiteralPath $ready).Hash.ToLowerInvariant() -cne $expected -or (Get-FileHash -LiteralPath $existing).Hash -cne $existingHash -or (Test-Path -LiteralPath $target)){throw 'Snapshot alterou sentinelas'}
$root=Join-Path $PSScriptRoot ('.runtime-snapshot-busca-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
@{criteria=$n;module_sha256=(Get-FileHash (Join-Path $repo 'publicacao_pendente.ps1')).Hash;scope='snapshot v3 dados/sentinelas; nao audio/plano/retomada/CLI'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'prova.json') -Encoding utf8
'SNAPSHOT_SEARCH_PASS criterios'+$n+'; '+$root
