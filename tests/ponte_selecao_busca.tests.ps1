#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
foreach($file in @('consulta_busca.ps1','selecao_automatica.ps1','selecao_busca.ps1','selecao_tecnica.ps1','execucao_unica.ps1')){. (Join-Path $repo $file)}
# Origem independente: contrato literal revisado da suite v3; nao executar a suite.
$fixturePath=Join-Path $PSScriptRoot 'selecao_busca_releitura.tests.ps1'
if((Get-FileHash $fixturePath).Hash -cne '5796DA1850C2357B6722BDEAAA6B53D4990FF618E967F97300153AE722EFCD08'){throw 'Origem da fixture alterada'}
$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile($fixturePath,[ref]$t,[ref]$e)
if($e.Count){throw 'Fixture nao parseavel'}
foreach($name in @('id','url','literal')){
 $assignment=@($a.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.AssignmentStatementAst] -and $_.Left -is [Management.Automation.Language.VariableExpressionAst] -and $_.Left.VariablePath.UserPath -ceq $name})
 if($assignment.Count -ne 1){throw 'Atribuicao literal ambigua'}
 . ([scriptblock]::Create($assignment[0].Extent.Text))
}
$assertPath=Join-Path $PSScriptRoot 'selecao_busca_construtor.tests.ps1'
if((Get-FileHash $assertPath).Hash -cne '4BD9B15ACAE6097EB49F3F44D4E68FF1DB8BE85EAEF0E1F3649A18BFEAAEF4E4'){throw 'Assercao alterada'}
$a=[Management.Automation.Language.Parser]::ParseFile($assertPath,[ref]$t,[ref]$e)
$helper=@($a.FindAll({param($x)$x -is [Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -ceq 'Assert-Literal'},$false))
if($e.Count -or $helper.Count -ne 1){throw 'Assercao ausente'}
# Comparador local aceita bool somente como bool.
$assertSource=$helper[0].Extent.Text
$numeric=' }elseif($actual -isnot [int] -or $actual -ne $literal){throw ''Tipo/numero literal divergiu''}'
$typed=@'
 }elseif($literal -is [bool]){
  if($actual -isnot [bool] -or $actual -ne $literal){throw 'Booleano literal divergiu'}
 }elseif($actual -isnot [int] -or $actual -ne $literal){throw 'Tipo/numero literal divergiu'}
'@
if(([regex]::Matches($assertSource,[regex]::Escape($numeric))).Count -ne 1){throw 'Ancora comparador ambigua'}
$assertSource=$assertSource.Replace($numeric,$typed)
. ([scriptblock]::Create($assertSource))
function Copy-Proof {$literal|ConvertTo-Json -Depth 12|ConvertFrom-Json -AsHashtable}
function Bridge-Args($proof){@{VideoId=$id;SourceUrl=$url;Artist='Artista';Song='Faixa';Record=@{selecao_tecnica=$proof}}}
function Check-Null($parameters){if($null -ne (Resolve-PublicationSelectionProof @parameters)){throw 'Entrada invalida aceita/fallback indevido'};$script:n++}
$n=0
$parameters=Bridge-Args $literal
$r=Resolve-PublicationSelectionProof @parameters
Assert-Literal $r @{Kind='technical_v3';Field='selecao_tecnica';Proof=$literal};$n++
if([object]::ReferenceEquals($r.Proof,$literal) -or [object]::ReferenceEquals($r.Proof.referencia,$literal.referencia)){throw 'Alias da prova'}
$r.Proof.referencia.artista='mutado'
if($literal.referencia.artista -cne 'Artista'){throw 'Entrada alterada'};$n++
$v2=@{versao=[int]2;tipo='selecao_tecnica';video_id=$id;criterio='url_direta_id_literal';metadados=@{id=$id;title='Entrevista com voz'};referencia=@{artista='Artista';musica='Faixa'}}
$r=Resolve-PublicationSelectionProof $id 'Artista' 'Faixa' @{selecao_tecnica=$v2}
Assert-Literal $r @{Kind='technical_v2';Field='selecao_tecnica';Proof=$v2};$n++
$raw=@{VideoId=$id;ArtistaMusicaConferidos='SIM';VersaoConferida='SIM';SemVocaisConferido='SIM'}
$legacy=Resolve-MusicalApprovalProof -VideoId $id -Artist Artista -Song Faixa -RawApproval $raw
if($null -eq $legacy){throw 'Fixture legado nao valida'}
$r=Resolve-PublicationSelectionProof -VideoId $id -Artist Artista -Song Faixa -Record @{aprovacao_musical=$legacy}
Assert-Literal $r @{Kind='legacy_human_v1';Field='aprovacao_musical';Proof=$legacy}
if($r.Proof.versao -ne 1 -or -not $r.Proof.sem_vocais_conferido -or -not $r.Proof.versao_conferida -or -not $r.Proof.artista_musica_conferidos){throw 'Legado alterado'};$n++
$parameters=Bridge-Args (Copy-Proof);$parameters.Remove('SourceUrl');Check-Null $parameters
foreach($key in @('VideoId','Artist','Song','SourceUrl')){
 $parameters=Bridge-Args (Copy-Proof)
 $parameters[$key]=switch($key){VideoId{'OtherId0123'}Artist{'Outro'}Song{'Outra'}SourceUrl{'https://www.youtube.com/results?search_query=Artista%20Faixa'}}
 Check-Null $parameters
}
$invalid=@($null,@{},@{versao='3'})
foreach($version in @(1,2,'3')){$s=Copy-Proof;$s.versao=$version;$invalid+=,$s}
$s=Copy-Proof;$s.referencia.consulta='forjada';$invalid+=,$s
$s=Copy-Proof;$s.metadados.id='OtherId0123';$invalid+=,$s
foreach($s in $invalid){$parameters=Bridge-Args $s;$parameters.Record.aprovacao_musical=$legacy;Check-Null $parameters}
foreach($field in @('Selecao_tecnica','Aprovacao_musical')){
 $parameters=Bridge-Args (Copy-Proof)
 if($field -ceq 'Selecao_tecnica'){$parameters.Record=@{Selecao_tecnica=$literal;aprovacao_musical=$legacy}}
 else{$parameters.Record.Aprovacao_musical=$legacy}
 Check-Null $parameters
}
if($null -ne (Resolve-PublicationSelectionProof)){throw 'Default aceito'};$n++
$parameters=Bridge-Args (Copy-Proof);$parameters.Record.aprovacao_musical=$legacy
$r=Resolve-PublicationSelectionProof @parameters
Assert-Literal $r @{Kind='technical_v3';Field='selecao_tecnica';Proof=$literal};$n++
$ps=[powershell]::Create()
try{
 $setup='$ErrorActionPreference=''Stop'''+[Environment]::NewLine+[IO.File]::ReadAllText((Join-Path $repo 'selecao_tecnica.ps1'))
 $parameters=Bridge-Args (Copy-Proof)
 $null=$ps.AddScript($setup).AddStatement().AddCommand('Resolve-PublicationSelectionProof').AddParameters($parameters)
 try{$null=$ps.Invoke()}catch{if($ps.Streams.Error.Count -eq 0){throw}}
 if(-not $ps.HadErrors -or $ps.Streams.Error.Count -ne 1 -or $ps.Streams.Error[0].FullyQualifiedErrorId -cne 'CommandNotFoundException,Resolve-PublicationSelectionProof' -or -not $ps.Streams.Error[0].Exception.Message.Contains('Resolve-AutoSearchAudioSelectionProof',[StringComparison]::Ordinal)){throw 'Dependencia ausente mascarada'}
}finally{$ps.Dispose()}
$n++
$root=Join-Path $PSScriptRoot ('.runtime-ponte-busca-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $root
@{criteria=$n;module_sha256=(Get-FileHash (Join-Path $repo 'selecao_tecnica.ps1')).Hash;scope='ponte pura v3/v2/v1; nao CLI/publicacao'}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $root 'prova.json') -Encoding utf8
'BRIDGE_SEARCH_PASS criterios'+$n+'; '+$root
