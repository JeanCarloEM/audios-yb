#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=Split-Path $PSScriptRoot -Parent
$work=Join-Path $PSScriptRoot ('.runtime-integration-'+[guid]::NewGuid().ToString('N'))
$case=Join-Path $work 'script com acento á'
$foreign=Join-Path $work 'cwd externo'
[void][IO.Directory]::CreateDirectory($case)
[void][IO.Directory]::CreateDirectory($foreign)
foreach($name in @('baixar_audios_ytdlp.ps1','ambiente_portatil.ps1','ferramentas_portateis.ps1','execucao_unica.ps1','evidencias_fonte.ps1','autenticacao_ytdlp.ps1','yt-dlp.exe','ffmpeg.exe','ffprobe.exe')){
 [IO.File]::Copy((Join-Path $repo $name),(Join-Path $case $name))
}
$csv=Join-Path $case 'fonte canônica.csv'
$url='https://www.youtube.com/watch?v=CSVsource01'
[pscustomobject]@{Ordem='1';Artista='Fixture';Musica='Musica';Link_YouTube=$url;Tipo_link='Direto';Verificacao='Fixture';Observacoes='Sem rede'}|Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding utf8BOM
[IO.File]::WriteAllText((Join-Path $foreign 'fonte canônica.csv'),'CSV isca invalido')
$before=(Get-FileHash -LiteralPath $csv).Hash
$pwsh=(Get-Process -Id $PID).Path
$old=Get-Location
try {
 foreach($cwd in @($repo,$foreign)){
  Set-Location -LiteralPath $cwd
  $log=& $pwsh -NoProfile -File (Join-Path $case 'baixar_audios_ytdlp.ps1') -SomenteAuditarExistentes -NaoInterativo 2>&1
  if($LASTEXITCODE -ne 0){throw ($log|Out-String)}
  $state=Get-Content -LiteralPath (Join-Path (Join-Path $case 'destino') '.controle/estado.json') -Raw|ConvertFrom-Json
  $records=@($state.registros.PSObject.Properties.Value)
  if($records.Count -ne 1 -or $records[0].url_original -cne $url){throw 'Principal nao usou CSV canonico descoberto'}
  if($cwd -eq $foreign -and (Test-Path -LiteralPath (Join-Path $cwd 'destino/.controle/estado.json'))){throw 'Escreveu destino no cwd'}
 }
 if((Get-FileHash -LiteralPath $csv).Hash -cne $before){throw 'CSV modificado'}
} finally {Set-Location -LiteralPath $old}
$t=$null;$e=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'baixar_audios_ytdlp.ps1'),[ref]$t,[ref]$e)
if($e.Count){throw 'Sintaxe principal invalida'}
$f=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-Ytdlp'},$true))
. ([scriptblock]::Create($f[0].Extent.Text))
$echo=Join-Path $work 'eco argumentos.ps1'
[IO.File]::WriteAllText($echo,'param([Parameter(ValueFromRemainingArguments=$true)][AllowEmptyString()][string[]]$Values) [Console]::OutputEncoding=[Text.UTF8Encoding]::new($false); [Console]::WriteLine((ConvertTo-Json -InputObject @($Values) -Compress))')
$script:Root=$case
$values=@('com espaco','aspas"literais','ação','; exit 99','$(inexistente)','')
$run=Invoke-Ytdlp -Executable $pwsh -Arguments (@('-NoProfile','-File',$echo)+$values) -TimeoutSeconds 20
if($run.code -ne 0){throw $run.err}
$got=@($run.out|ConvertFrom-Json)
if($got.Count -ne $values.Count){throw 'Perdeu argumentos'}
for($i=0;$i -lt $values.Count;$i++){if($got[$i] -cne $values[$i]){throw ('Argumento alterado: '+$i)}}
# Sem yt-dlp: inicializacao deve falhar antes de criar destino/estado.
$missing=Join-Path $work 'ferramenta ausente'
[void][IO.Directory]::CreateDirectory($missing)
foreach($name in @('baixar_audios_ytdlp.ps1','ambiente_portatil.ps1','ferramentas_portateis.ps1','execucao_unica.ps1','evidencias_fonte.ps1','autenticacao_ytdlp.ps1')){
 [IO.File]::Copy((Join-Path $repo $name),(Join-Path $missing $name))
}
$failedLog=& $pwsh -NoProfile -File (Join-Path $missing 'baixar_audios_ytdlp.ps1') -SomenteAuditarExistentes -NaoInterativo 2>&1
if($LASTEXITCODE -ne 2 -or ($failedLog|Out-String) -notmatch 'yt-dlp.exe'){throw 'Preflight nao diagnosticou dependencia ausente'}
if(Test-Path -LiteralPath (Join-Path $missing 'destino')){throw 'Preflight ausente criou destino'}
Write-Output 'INTEGRACAO_PORTATIL_PASS: CSV automatico/URL canonica, dois cwd, processo argv real; sem rede/browser'