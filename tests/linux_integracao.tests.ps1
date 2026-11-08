#requires -Version 7.0
param(
 [string]$ToolsReceipt=(Join-Path $PSScriptRoot '.runtime-linux-tools/receipt.json'),
 [string]$ExpectedCsv=(Join-Path $PSScriptRoot '.runtime-linux-tools/canonical_csv_expected.json'),
 [string]$ResumeFixture
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
if(-not $IsLinux){throw 'Este roteiro exige Linux real; nao simular a plataforma'}
$repo=Split-Path $PSScriptRoot -Parent
$receipt=Get-Content -LiteralPath $ToolsReceipt -Raw -Encoding UTF8|ConvertFrom-Json
$expected=Get-Content -LiteralPath $ExpectedCsv -Raw -Encoding UTF8|ConvertFrom-Json
$tools=@{Exe=$receipt.versions.'yt-dlp'.path;Ffmpeg=$receipt.versions.ffmpeg.path;Ffprobe=$receipt.versions.ffprobe.path}
foreach($key in $tools.Keys){if(-not [IO.File]::Exists($tools[$key])){throw ('Ferramenta ausente: '+$key)}}
$work=if($ResumeFixture){
 $resolved=[IO.Path]::GetFullPath($ResumeFixture)
 if(-not [IO.Directory]::Exists($resolved) -or [IO.Path]::GetDirectoryName($resolved) -cne [IO.Path]::GetFullPath($PSScriptRoot) -or [IO.Path]::GetFileName($resolved) -notmatch '^\.runtime-linux-integration-[a-f0-9]{32}$'){throw 'ResumeFixture fora dos artefatos permitidos'}
 foreach($pending in @('PE rejeitado')){if(Test-Path -LiteralPath (Join-Path $resolved $pending)){throw ('Etapa ja iniciada; nao repetir: '+$pending)}}
 $resolved
}else{Join-Path $PSScriptRoot ('.runtime-linux-integration-'+[guid]::NewGuid().ToString('N'))}
$caseRoot=$work
if($receipt.schema -ceq 'audios-yb-linux-native-environment/v1'){
 if($receipt.stage -cne 'READY'){throw 'Ambiente nativo nao pronto'}
 $nativeRoot=[IO.Path]::GetFullPath([string]$receipt.root)
 if([IO.Path]::GetDirectoryName($nativeRoot) -cne '/tmp' -or [IO.Path]::GetFileName($nativeRoot) -notmatch '^audios-yb-native-[a-zA-Z0-9_-]+$' -or -not [IO.Directory]::Exists($nativeRoot)){throw 'Raiz nativa invalida'}
 $caseRoot=Join-Path $nativeRoot ('cases-'+[guid]::NewGuid().ToString('N'))
}
$foreign=Join-Path $caseRoot 'cwd externo'
[void][IO.Directory]::CreateDirectory($foreign)
$source=[IO.File]::ReadAllText((Join-Path $repo 'baixar_audios_ytdlp.ps1'))
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Sintaxe de producao invalida'}
$main=@($ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]})
if($main.Count -ne 1){throw 'Entrada principal ambigua'}
$mocks=@'
$script:LinuxFixture=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixture.json') -Raw|ConvertFrom-Json
function Read-InRunValue {throw 'Pergunta indevida no fluxo autonomo Linux'}
function Search-Candidates {throw 'Busca externa indevida na fixture Linux'}
function Get-Info([string]$Id){
 $info=[pscustomobject]@{id=$Id;title='Fixture - Ruido';channel='Fixture - Topic';uploader='Fixture';artist='Fixture';track='Ruido';duration=4}
 $fmt=@{id='192';ext='mp3';codec='mp3';abr=192;tier=0;quality=64;operacao='nativo';filesize=(Get-Item -LiteralPath $script:LinuxFixture.source).Length;duracao_origem=4}
 return @{ok=$true;info=$info;formats=@($fmt);run=@{tentativas=1}}
}
function Invoke-Checked([string[]]$Arguments,[int]$Timeout=100){
 if($Arguments -contains '--cookies' -or $Arguments -contains '--cookies-from-browser'){throw 'Sessao de navegador/cookies inesperada'}
 $i=[array]::IndexOf($Arguments,'--output')
 if($i -lt 0 -or $Arguments -notcontains '--no-overwrites'){throw 'Contrato de download inesperado'}
 $target=$Arguments[$i+1].Replace('%(ext)s','mp3')
 if([IO.File]::Exists($target)){throw 'Fixture tentou baixar fonte novamente'}
 [IO.File]::Copy($script:LinuxFixture.source,$target,$false)
 [IO.File]::AppendAllText((Join-Path $PSScriptRoot 'download_calls.txt'),'1')
 return @{code=0;tentativas=1;out='fixture local';err='';timeout=$false}
}
'@
$mockSource=$source.Insert($main[0].Extent.StartOffset,$mocks+[Environment]::NewLine)
function Assert($Ok,[string]$Why){if(-not $Ok){throw $Why}}
function New-Case([string]$Name,[switch]$Mock,[switch]$Poison){
 $dir=Join-Path $caseRoot $Name
 if([IO.Directory]::Exists($dir)){
  if(-not $ResumeFixture -or -not $Mock){throw 'Caso existente nao pode ser repetido'}
  if((Test-Path -LiteralPath (Join-Path $dir 'destino')) -or (Test-Path -LiteralPath (Join-Path $dir 'download_calls.txt'))){throw 'Publicacao ja iniciada: reconciliar'}
  Assert ([IO.File]::ReadAllText((Join-Path $dir 'baixar_audios_ytdlp.ps1')) -ceq $mockSource) 'Main da fixture mudou'
  foreach($helper in @('ambiente_portatil.ps1','ferramentas_portateis.ps1','execucao_unica.ps1','evidencias_fonte.ps1','autenticacao_ytdlp.ps1','publicacao_pendente.ps1','referencia_publicacao.ps1')){
   Assert ((Get-FileHash -LiteralPath (Join-Path $repo $helper)).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $dir $helper)).Hash) ('Helper da fixture mudou: '+$helper)
  }
  Assert ([IO.File]::Exists((Join-Path $dir 'fonte conhecida.mp3'))) 'Fonte sintetica ausente'
  Write-Host 'REUSE LINUX prepared synthetic source; product had no filesystem effects'
  return $dir
 }
 [void][IO.Directory]::CreateDirectory($dir)
 foreach($helper in @('ambiente_portatil.ps1','ferramentas_portateis.ps1','execucao_unica.ps1','evidencias_fonte.ps1','autenticacao_ytdlp.ps1','publicacao_pendente.ps1','referencia_publicacao.ps1')){[IO.File]::Copy((Join-Path $repo $helper),(Join-Path $dir $helper))}
 [IO.File]::WriteAllText((Join-Path $dir 'baixar_audios_ytdlp.ps1'),$(if($Mock){$mockSource}else{$source}),[Text.UTF8Encoding]::new($true))
 $files=@{ffmpeg=$tools.Ffmpeg;ffprobe=$tools.Ffprobe}
 if(-not $Poison){$files['yt-dlp_linux']=$tools.Exe}
 foreach($name in $files.Keys){
  $target=Join-Path $dir $name
  try{[void][IO.File]::CreateSymbolicLink($target,$files[$name])}catch{[IO.File]::Copy($files[$name],$target,$false)}
 }
 if($Poison){[IO.File]::WriteAllBytes((Join-Path $dir 'yt-dlp_linux'),[byte[]](77,90,0,0))}
 return $dir
}
function Run-Case([string]$Dir,[hashtable]$Options,[string]$LogName='run.log'){
 Push-Location $foreign
 $cliArgs=@('-NoLogo','-NoProfile','-NonInteractive','-File',(Join-Path $Dir 'baixar_audios_ytdlp.ps1'))
 foreach($key in @($Options.Keys|Sort-Object)){
  if($Options[$key] -is [bool]){if($Options[$key]){$cliArgs+=('-'+$key)}}else{$cliArgs+=@(('-'+$key),([string]$Options[$key]))}
 }
 try{& $receipt.versions.pwsh.path @cliArgs *> (Join-Path $Dir $LogName);$runExit=$LASTEXITCODE}finally{Pop-Location}
 return $runExit
}
# Expectativas do CSV produzidas pelo csv da biblioteca Python, fora do leitor do produto.
$canonical=Join-Path $repo $expected.source_name
Assert ((Get-FileHash -LiteralPath $canonical).Hash.ToLowerInvariant() -ceq $expected.sha256) 'Fonte canonica mudou apos referencia independente'
$audit=Join-Path $work 'auditoria canonica com acento á'
if($ResumeFixture){
 foreach($name in @('baixar_audios_ytdlp.ps1','ambiente_portatil.ps1','ferramentas_portateis.ps1','execucao_unica.ps1','evidencias_fonte.ps1','autenticacao_ytdlp.ps1','publicacao_pendente.ps1','referencia_publicacao.ps1')){
  $current=Join-Path $repo $name;$cached=Join-Path $audit $name
  Assert ((Get-FileHash -LiteralPath $current).Hash -ceq (Get-FileHash -LiteralPath $cached).Hash) ('Fonte da auditoria anterior mudou: '+$name)
 }
 Assert ((Get-FileHash -LiteralPath (Join-Path $audit $expected.source_name)).Hash.ToLowerInvariant() -ceq $expected.sha256) 'CSV da auditoria anterior divergiu'
 Write-Output 'REUSE LINUX canonical audit artifacts; previous native exit was not measured'
}else{
 $audit=New-Case 'auditoria canonica com acento á'
 [IO.File]::Copy($canonical,(Join-Path $audit $expected.source_name))
 Assert ((Run-Case $audit @{SomenteAuditarExistentes=$true}) -eq 0) 'Auditoria Linux falhou'
}
$statePath=Join-Path $audit 'destino/.controle/estado.json'
$state=Get-Content -LiteralPath $statePath -Raw -Encoding UTF8|ConvertFrom-Json
$records=@($state.registros.PSObject.Properties.Value)
Assert ($records.Count -eq $expected.records.Count) 'Quantidade divergiu da fonte canonica'
$byOrder=@{};foreach($row in $expected.records){$byOrder[[string]$row.ordem]=[string]$row.url}
foreach($r in $records){Assert ($byOrder.ContainsKey([string]$r.ordem) -and [string]$r.url_original -ceq $byOrder[[string]$r.ordem]) 'URL de estado divergiu do CSV'}
$report=@(Import-Csv -LiteralPath (Join-Path $audit 'destino/.controle/relatorio.csv') -Encoding UTF8)
Assert ($report.Count -eq $expected.records.Count) 'Relatorio incompleto'
for($i=0;$i -lt $report.Count;$i++){Assert ([string]$report[$i].Ordem -ceq [string]$expected.records[$i].ordem -and [string]$report[$i].URL_original -ceq [string]$expected.records[$i].url) 'Ordem/URL no relatorio alteradas'}
Assert (-not (Test-Path -LiteralPath (Join-Path $foreign 'destino'))) 'Cwd alterou o destino'
Assert ((Get-FileHash -LiteralPath (Join-Path $audit $expected.source_name)).Hash.ToLowerInvariant() -ceq $expected.sha256) 'Copia do CSV modificada'
Write-Output ('PASS LINUX canonical_csv registros='+$records.Count+' ordem/URLs/hash sem rede')
# Audio sintetico independente, ferramentas ELF reais; somente metadados/transporte simulados.
$media=New-Case 'audio com espaço ação' -Mock
$seed=Join-Path $media 'fonte conhecida.mp3'
if($ResumeFixture -and $caseRoot -cne $work){
 $preparedSeed=Join-Path (Join-Path $work 'audio com espaço ação') 'fonte conhecida.mp3'
 Assert ([IO.File]::Exists($preparedSeed)) 'Fonte sintetica anterior ausente'
 [IO.File]::Copy($preparedSeed,$seed,$false)
 Assert ((Get-FileHash -LiteralPath $seed).Hash -ceq (Get-FileHash -LiteralPath $preparedSeed).Hash) 'Copia da fonte sintetica divergiu'
}
if(-not [IO.File]::Exists($seed)){
 & $tools.Ffmpeg -nostdin -v error -f lavfi -i 'anoisesrc=sample_rate=44100:duration=4:seed=1' -ac 2 -c:a libmp3lame -b:a 192k -n $seed
 Assert ($LASTEXITCODE -eq 0) 'Geracao de audio Linux falhou'
}
$hash=(Get-FileHash -LiteralPath $seed).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $media 'fixture.json'),(ConvertTo-Json @{source=$seed} -Depth 4))
[pscustomobject]@{Ordem='1';Artista='Fixture';Musica='Ruido';Link_YouTube='https://www.youtube.com/watch?v=TestVideo01';Tipo_link='Direto';Verificacao='Fixture';Observacoes='Audio sintetico conhecido'}|Export-Csv -LiteralPath (Join-Path $media 'entrada.csv') -NoTypeInformation -Encoding UTF8
[pscustomobject]@{Ordem='1';VideoId='TestVideo01';ArtistaMusicaConferidos='SIM';VersaoConferida='SIM';SemVocaisConferido='SIM'}|Export-Csv -LiteralPath (Join-Path $media 'aprovacoes.csv') -NoTypeInformation -Encoding UTF8
$doc=Join-Path $media 'origem.txt'
[IO.File]::WriteAllText($doc,'Ruido PCM local sintetico gerado e codificado uma unica vez em MP3 CBR192; fixture conhecida, sem vocais.')
$entry=@{video_id='TestVideo01';formato_id='192';sha256=$hash;origem='Fixture sintetica local FFmpeg';historico='Ruido PCM conhecido codificado uma unica vez em MP3 CBR192';qualidade='perdas_verificadas';bitrate_minimo_historico_kbps=192;documento='origem.txt';documento_sha256=(Get-FileHash -LiteralPath $doc).Hash.ToLowerInvariant()}
[IO.File]::WriteAllText((Join-Path $media 'evidencia-fixture.json'),(ConvertTo-Json -InputObject @($entry) -Depth 8))
Assert ((Run-Case $media @{AprovacoesCsv='aprovacoes.csv'} 'publicacao.argv-corrigido.log') -eq 0) 'Publicacao Linux fatal'
$mediaStatePath=Join-Path $media 'destino/.controle/estado.json'
$ms=Get-Content -LiteralPath $mediaStatePath -Raw -Encoding UTF8|ConvertFrom-Json
$mr=@($ms.registros.PSObject.Properties.Value)[0]
Assert ($mr.resultado -eq 'baixado' -and $mr.auditoria.validado -and $mr.aprovacao_musical.sem_vocais_conferido) ('Nao publicou com provas: '+$mr.motivo)
$final=Join-Path (Join-Path $media 'destino') $mr.arquivo
Assert ((Get-FileHash -LiteralPath $final).Hash.ToLowerInvariant() -ceq $hash) 'Nativo alterado'
Assert ((Run-Case $media @{} 'reuso.log') -eq 0) 'Reuso Linux fatal'
$ms=Get-Content -LiteralPath $mediaStatePath -Raw -Encoding UTF8|ConvertFrom-Json
$mr=@($ms.registros.PSObject.Properties.Value)[0]
Assert ($mr.resultado -eq 'existente') ('Reuso nao confirmado: '+$mr.motivo)
Assert (([IO.File]::ReadAllText((Join-Path $media 'download_calls.txt'))) -ceq '1') 'Download repetido'
Assert ((Get-FileHash -LiteralPath $final).Hash.ToLowerInvariant() -ceq $hash) 'Reuso alterou bytes'
Write-Output 'PASS LINUX publicacao/reuso sem perguntas/cookies; hash nativo preservado; transporte simulado'
$pe=New-Case 'PE rejeitado' -Poison
Assert ((Run-Case $pe @{}) -eq 2) 'PE nao rejeitado'
Assert (([IO.File]::ReadAllText((Join-Path $pe 'run.log'))) -match 'Windows PE') 'Erro PE nao causal'
Assert (-not (Test-Path -LiteralPath (Join-Path $pe 'destino'))) 'PE gerou efeitos no lote'
Assert ((Get-FileHash -LiteralPath $canonical).Hash.ToLowerInvariant() -ceq $expected.sha256) 'CSV canonico original modificado'
$summary=@{platform=[Runtime.InteropServices.RuntimeInformation]::OSDescription;ps=[string]$PSVersionTable.PSVersion;canonical_records=$records.Count;canonical_sha256=$expected.sha256;audio_sha256=$hash;canonical_audit_reused=[bool]$ResumeFixture;transport='simulado';questions=0;downloads=1;reuse='existente';pe_rejected=$true;fixture_root=$work;case_root=$caseRoot;audit_root=$audit}
[IO.File]::WriteAllText((Join-Path $caseRoot 'receipt.json'),(ConvertTo-Json $summary -Depth 5))
Write-Output ('LINUX_PROJECT_INTEGRATION_PASS receipt='+(Join-Path $caseRoot 'receipt.json'))
