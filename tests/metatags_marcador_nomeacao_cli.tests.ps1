#requires -Version 7
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$base=Join-Path $PSScriptRoot 'metatags_cli.tests.ps1'
if((Get-FileHash -LiteralPath $base).Hash -cne '09B1433827C878D459B74CD5A4BE05A89742031BF3EE93800E16CA7E7F1D4746'){throw 'Teste base mudou'}
$source=[IO.File]::ReadAllText($base)
function Quote-Combo([string]$Value){return ([string][char]39+$Value.Replace([string][char]39,([string][char]39+[char]39))+[char]39)}
function Put-ComboLiteral([string]$Text,[object]$Node,[string]$Value){
 if([regex]::Matches($Text,[regex]::Escape($Node.Extent.Text)).Count -ne 1){throw 'Literal nao unico'}
 return $Text.Replace($Node.Extent.Text,(Quote-Combo $Value))
}
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e.Count){throw 'Base parse'}
$extNodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value.Contains('$copyExtra=') -and $n.Value.Contains(' -Metatags -ColunaAlbumTag Album')},$true))
if($extNodes.Count -ne 1){throw 'Extension nao unica'}
$extension=$extNodes[0].Value
$t=$null;$e=$null;$ea=[Management.Automation.Language.Parser]::ParseInput($extension,[ref]$t,[ref]$e)
if($e.Count){throw 'Extension parse'}
$callNodes=@($ea.FindAll({param($n)$n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value.Contains(' -Metatags -ColunaAlbumTag Album')},$true))
$copyNodes=@($ea.FindAll({param($n)$n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value.Contains('preparo_metatags_editoriais.ps1')},$true))
$hookNodes=@($ea.FindAll({param($n)$n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value.Contains('$sourceHashBeforeTags=') -and $n.Value.Contains('$tagProbe=$probeRun.Stdout')},$true))
if($callNodes.Count -ne 1 -or $copyNodes.Count -ne 1 -or $hookNodes.Count -ne 1){throw 'Catalogo combo nao unico'}
$tail=' -ColunaAutorTag Autor }'
if([regex]::Matches($callNodes[0].Value,[regex]::Escape($tail)).Count -ne 1){throw 'Invocation tail'}
$call=$callNodes[0].Value.Replace($tail,' -ColunaAutorTag Autor -Marcador ''Grupo DJ'' -ModeloNome Musical -ColunaAutor Autor -ColunaTrack Numero -ColunaTitulo Musica -LarguraTrack 3 }')
$oldCopy='''preparo_metatags_editoriais.ps1'''
if([regex]::Matches($copyNodes[0].Value,[regex]::Escape($oldCopy)).Count -ne 1){throw 'Copy tail'}
$copy=$copyNodes[0].Value.Replace($oldCopy,'''preparo_metatags_editoriais.ps1'',''nomeacao_editorial.ps1'',''mapeamento_nomeacao.ps1''')
$checks='  if(-not [string]::Equals([string]$tagProbe.format.tags.marcador_coletanea,''Grupo dj'',[StringComparison]::Ordinal)){throw ''Marcador final divergente''}
  $markerAudit=$record.auditoria.marcador
  $tagAudit=$record.auditoria.metatags
  if($markerAudit.status -cne ''aplicado'' -or $markerAudit.encadeamento -cne ''metatags_editoriais''){throw ''Encadeamento marcador/metatags ausente''}
  if(([string]$markerAudit.origem_sha256).ToLowerInvariant() -cne $sourceHashBeforeTags -or ([string]$markerAudit.resultado_intermediario_sha256).ToLowerInvariant() -ceq $sourceHashBeforeTags -or ([string]$markerAudit.resultado_intermediario_sha256).ToLowerInvariant() -cne ([string]$tagAudit.origem_sha256).ToLowerInvariant() -or ([string]$markerAudit.resultado_sha256).ToLowerInvariant() -cne $finalHash){throw ''Cadeia hashes marcador/metatags divergente''}
  if($record.nomeacao.modelo_solicitado -cne ''Musical'' -or $record.nomeacao.modelo_aplicado -cne ''Musical''){throw ''Nomeacao musical nao aplicada''}
  foreach($component in @(''Compositor'',''003'',''Faixa'',''TestVideo01'')){if($finals[0].Name.IndexOf($component,[StringComparison]::Ordinal) -lt 0){throw (''Nome final sem componente literal: ''+$component)}}
  Write-Output ''METATAGS_MARKER_NAMING_APPLY_PASS''
'
$hookAnchor='  $tagProbe=$probeRun.Stdout|ConvertFrom-Json'
if([regex]::Matches($hookNodes[0].Value,[regex]::Escape($hookAnchor)).Count -ne 1){throw 'Native hook anchor'}
$hook=$hookNodes[0].Value.Replace($hookAnchor,$hookAnchor+[char]10+$checks)
$extension=Put-ComboLiteral $extension $callNodes[0] $call
$extension=Put-ComboLiteral $extension $copyNodes[0] $copy
$extension=Put-ComboLiteral $extension $hookNodes[0] $hook
$source=Put-ComboLiteral $source $extNodes[0] $extension
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e.Count){throw 'Stage combo parse'}
$journalNodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value.Contains('METATAGS_CLI_JOURNAL_PASS')},$true))
if($journalNodes.Count -ne 1){throw 'Journal hook nao unico'}
$journal=' $markerJournal=$journal.Data.auditoria.marcador
 $tagJournal=$journal.Data.auditoria.metatags
 if($markerJournal.status -cne ''aplicado'' -or ([string]$markerJournal.resultado_intermediario_sha256).ToLowerInvariant() -cne ([string]$tagJournal.origem_sha256).ToLowerInvariant() -or ([string]$markerJournal.resultado_sha256).ToLowerInvariant() -cne $hash -or $journal.Data.registro.nomeacao.modelo_aplicado -cne ''Musical''){throw ''Journal perdeu cadeia/nomeacao''}
 Write-Output ''METATAGS_MARKER_NAMING_JOURNAL_PASS''
'
$source=Put-ComboLiteral $source $journalNodes[0] ($journalNodes[0].Value+[char]10+$journal)
$t=$null;$e=$null;$rootAst=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e.Count){throw 'Root source parse'}
$rootNodes=@($rootAst.FindAll({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$repo' -and $n.Right.Extent.Text -ceq 'Split-Path -Parent $PSScriptRoot'},$true))
if($rootNodes.Count -ne 1){throw 'Atribuicao root nao unica'}
$rootNode=$rootNodes[0]
$source=$source.Remove($rootNode.Extent.StartOffset,$rootNode.Extent.EndOffset-$rootNode.Extent.StartOffset).Insert($rootNode.Extent.StartOffset,('$repo='+(Quote-Combo $repo)))
$t=$null;$e=$null;$null=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e.Count){throw 'Combo final parse'}
$work=Join-Path $PSScriptRoot ('.runtime-metatags-combo-'+[guid]::NewGuid().ToString('N'));$null=[IO.Directory]::CreateDirectory($work)
$path=Join-Path $work 'metatags_combo.ps1'
[IO.File]::WriteAllText($path,$source,[Text.UTF8Encoding]::new($false))
. (Join-Path $repo 'tests/processo_capturado.ps1')
$r=Invoke-CapturedTestProcess -Program (Join-Path $PSHOME 'pwsh.exe') -Arguments @('-NoProfile','-NonInteractive','-File',$path) -TimeoutMs 240000
$log=Join-Path $work 'combo.log';[IO.File]::WriteAllText($log,($r.Stdout+[Environment]::NewLine+$r.Stderr),[Text.UTF8Encoding]::new($false))
if($r.ExitCode -ne 0 -or -not $r.Stdout.Contains('METATAGS_CLI_PASS: 2casos')){throw ('Combo falhou: '+$log)}
'METATAGS_MARKER_NAMING_CLI_PASS cases=2 normal/fault; cadeia/nomeacao/journal/reuso; artefatos='+$work
