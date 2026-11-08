#requires -Version 7
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$producer=Join-Path $repo 'tests/publicacao_produtor_cli.tests.ps1'
if((Get-FileHash -LiteralPath $producer).Hash -cne '59502B942A39451CF7DBD90785D1F809A86618142CB261D89102DAEF6D903F24'){throw 'Produtor de teste mudou'}
$driver=[IO.File]::ReadAllText($producer)
function Replace-MetadataLiteral([string]$Text,[string]$Before,[string]$After){
 if([regex]::Matches($Text,[regex]::Escape($Before)).Count -ne 1){throw ('Ancora metadata nao unica: '+$Before)}
 return $Text.Replace($Before,$After)
}
$qRepo="'"+$repo.Replace("'","''")+"'"
$driver=Replace-MetadataLiteral $driver '$repo=Split-Path -Parent $PSScriptRoot' ('$repo='+$qRepo)
$extension='$source=Replace-ProducerTestLiteral $source '' -b:a 128k -n $fixture'' '' -b:a 192k -threads 1 -n $fixture''
if([regex]::Matches($source,''CBR128'').Count -ne 2){throw ''Fixture document anchors''}
$source=$source.Replace(''CBR128'',''CBR192'')
$source=Replace-ProducerTestLiteral $source ''bitrate_minimo_historico_kbps=128'' ''bitrate_minimo_historico_kbps=192''
$copyAnchor='' $scriptPath=Join-Path $case ''''baixar_audios_ytdlp.ps1''''''
$copyExtra='' foreach($name in @(''''editorial_audio.ps1'''',''''decisao_metatags.ps1'''',''''argumentos_metatags_mp3.ps1'''',''''candidato_metatags_mp3.ps1'''',''''comparacao_tags_ordinal.ps1'''',''''mapa_tags_editoriais.ps1'''',''''validacao_tags_editoriais.ps1'''',''''validacao_candidato_metatags_mp3.ps1'''',''''plano_metatags_editoriais.ps1'''',''''leitura_campo_editorial.ps1'''',''''mapeamento_metatags_editoriais.ps1'''',''''preparo_metatags_editoriais.ps1'''')){[IO.File]::Copy((Join-Path $repo $name),(Join-Path $case $name),$false)}
''
$source=Replace-ProducerTestLiteral $source $copyAnchor ($copyExtra+$copyAnchor)
$source=Replace-ProducerTestLiteral $source ''Observacoes=''''Fixture sintetica''''})'' ''Observacoes=''''Fixture sintetica'''';Album=''''Coletânea'''';Numero=''''003'''';Autor=''''Compositor''''})''
$source=Replace-ProducerTestLiteral $source ''  else{ & $scriptPath -NaoInterativo:($mode -eq ''''nao_interativo'''') -Interativo:($mode -ne ''''nao_interativo'''') }'' ''  else{ & $scriptPath -NaoInterativo:($mode -eq ''''nao_interativo'''') -Interativo:($mode -ne ''''nao_interativo'''') -Metatags -ColunaAlbumTag Album -ColunaTrackTag Numero -ColunaAutorTag Autor }''
$source=Replace-ProducerTestLiteral $source ''  if((Get-FileHash -LiteralPath $finals[0].FullName).Hash.ToLowerInvariant() -ne $hash){throw ''''Nativo foi alterado''''}'' ''  $sourceHashBeforeTags=$hash
  $finalHash=(Get-FileHash -LiteralPath $finals[0].FullName).Hash.ToLowerInvariant()
  if($finalHash -ceq $sourceHashBeforeTags -or $record.auditoria.origem_sha256 -cne $sourceHashBeforeTags -or $record.auditoria.metatags.status -cne ''''aplicado'''' -or -not $record.auditoria.metatags.validado){throw ''''Enriquecimento/auditoria de origem nao comprovado''''}
  if(([string]$record.auditoria.metatags.resultado_sha256).ToLowerInvariant() -cne $finalHash -or $record.auditoria.resultado_sha256 -cne $finalHash -or $record.auditoria.metatags.resultado_bytes -ne $finals[0].Length){throw ''''Hash/tamanho final divergente''''}
  . (Join-Path $repo ''''tests/processo_capturado.ps1'''')
  $probeRun=Invoke-CapturedTestProcess -Program (Join-Path $repo ''''ffprobe.exe'''') -Arguments @(''''-v'''',''''error'''',''''-protocol_whitelist'''',''''file'''',''''-show_streams'''',''''-show_format'''',''''-of'''',''''json'''',''''-i'''',$finals[0].FullName) -TimeoutMs 30000
  $tagProbe=$probeRun.Stdout|ConvertFrom-Json
  if(@($tagProbe.streams).Count -ne 1 -or $tagProbe.streams[0].codec_name -cne ''''mp3''''){throw ''''Streams finais divergentes''''}
  foreach($tagPair in @{artist=''''Artista'''';title=''''Faixa'''';album=''''Coletânea'''';track=''''003'''';composer=''''Compositor''''}.GetEnumerator()){
   if(-not [string]::Equals([string]$tagProbe.format.tags.($tagPair.Key),$tagPair.Value,[StringComparison]::Ordinal)){throw (''''Tag final divergente: ''''+$tagPair.Key)}
  }
  $sourceHashText=(& (Join-Path $repo ''''ffmpeg.exe'''') -nostdin -v error -protocol_whitelist file -i $fixture -map 0:a:0 -c:a copy -f hash -hash sha256 - |Out-String).Trim()
  if($LASTEXITCODE -ne 0){throw ''''Hash payload fonte falhou''''}
  $finalHashText=(& (Join-Path $repo ''''ffmpeg.exe'''') -nostdin -v error -protocol_whitelist file -i $finals[0].FullName -map 0:a:0 -c:a copy -f hash -hash sha256 - |Out-String).Trim()
  if($LASTEXITCODE -ne 0 -or -not [string]::Equals($sourceHashText,$finalHashText,[StringComparison]::Ordinal)){throw ''''Payload fonte/final divergente''''}
  $digest=[regex]::Match($sourceHashText,''''^SHA256=([0-9a-fA-F]{64})$'''')
  if(-not $digest.Success -or ([string]$record.auditoria.metatags.payload_sha256).ToLowerInvariant() -cne $digest.Groups[1].Value.ToLowerInvariant()){throw ''''Auditoria payload divergente''''}
  [IO.File]::WriteAllText((Join-Path $case ''''metatags-proof.json''''),(@{SourceSha256=$sourceHashBeforeTags;FinalSha256=$finalHash;Payload=$digest.Groups[1].Value;FinalPath=$finals[0].FullName;Tags=$tagProbe.format.tags;Audit=$record.auditoria.metatags}|ConvertTo-Json -Depth 14),[Text.UTF8Encoding]::new($false))
  $hash=$finalHash
  Write-Output ''''METATAGS_CLI_APPLY_PASS''''
''
'
$extension += [Environment]::NewLine + '$source=Replace-ProducerTestLiteral $source ''$work=Join-Path $PSScriptRoot (''''.runtime-e2e-''''+[guid]::NewGuid().ToString(''''N''''))'' ''$work=Join-Path (Join-Path $repo ''''tests'''') (''''.runtime-me-''''+[guid]::NewGuid().ToString(''''N''''))''' + [Environment]::NewLine
$anchor='$extraMocks=@'+[char]39
$driver=Replace-MetadataLiteral $driver $anchor ($extension+[Environment]::NewLine+$anchor)
$journalAnchor=' $journal=Read-PublicationIntentFile -Path (Join-Path (Join-Path $control ''publicacoes_pendentes'') $reference.arquivo) -ExpectedSha256 $reference.sha256 -Control $control'
$journalCheck=' if($journal.Data.sha256 -cne $hash -or $journal.Data.auditoria.resultado_sha256 -cne $hash -or ([string]$journal.Data.auditoria.metatags.resultado_sha256).ToLowerInvariant() -cne $hash -or $journal.Data.auditoria.origem_sha256 -cne $sourceHashBeforeTags){throw ''Journal metatags/origem/final divergente''}
 Write-Output ''METATAGS_CLI_JOURNAL_PASS''
'
$driver=Replace-MetadataLiteral $driver $journalAnchor ($journalAnchor+[Environment]::NewLine+$journalCheck)
$work=Join-Path $PSScriptRoot ('.runtime-metatags-cli-'+[guid]::NewGuid().ToString('N'))
$null=[IO.Directory]::CreateDirectory($work)
$driverPath=Join-Path $work 'producer_metatags.ps1'
$t=$null;$e=$null;$null=[Management.Automation.Language.Parser]::ParseInput($driver,[ref]$t,[ref]$e)
if($e.Count){throw 'Driver derivado invalido'}
[IO.File]::WriteAllText($driverPath,$driver,[Text.UTF8Encoding]::new($false))
. (Join-Path $repo 'tests/processo_capturado.ps1')
$r=Invoke-CapturedTestProcess -Program (Join-Path $PSHOME 'pwsh.exe') -Arguments @('-NoProfile','-NonInteractive','-File',$driverPath) -TimeoutMs 240000
$log=Join-Path $work 'driver.log'
[IO.File]::WriteAllText($log,($r.Stdout+[Environment]::NewLine+$r.Stderr),[Text.UTF8Encoding]::new($false))
if($r.ExitCode -ne 0 -or -not $r.Stdout.Contains('PUBLICATION_PRODUCER_CLI_PASS')){throw ('CLI metadata falhou; log='+$log)}
'METATAGS_CLI_PASS: 2casos normal/IOaposMove; 5tags/MP3payload/origem-final/journal/reuso0transporte; artefatos='+$work
