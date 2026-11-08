#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$harness=Join-Path $repo 'tests/execucao_unica.tests.ps1'
if((Get-FileHash -LiteralPath $harness).Hash -cne '63917D9605ECBC278F57327DE88176403E2C51C588C2E1E44827425EA146CB9F'){throw 'Harness mudou: revisar adaptacao ISO'}
$source=[IO.File]::ReadAllText($harness)
$rootLine='$repo=Split-Path $PSScriptRoot -Parent'
if(([regex]::Matches($source,[regex]::Escape($rootLine))).Count -ne 1){throw 'Raiz do harness ambigua'}
foreach($required in @("track='Faixa'","Musica='Faixa'","title='Artista - Faixa'")){
 if(-not $source.Contains($required)){throw ('Fixture independente mudou: '+$required)}
}
$source=$source.Replace($rootLine,('$repo='+"'"+$repo.Replace("'","''")+"'"))
$source=$source.Replace('Faixa','2026-11-06T12:00:00Z')
$t=$null;$e=$null
[void][Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
if($e.Count){throw 'Clone ISO invalido'}
$work=Join-Path $PSScriptRoot ('.runtime-estado-strings-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$clone=Join-Path $work 'execucao_unica_iso.ps1'
[IO.File]::WriteAllText($clone,$source,[Text.UTF8Encoding]::new($false))
. (Join-Path $repo 'tests/processo_capturado.ps1')
$r=Invoke-CapturedTestProcess -Program (Join-Path $PSHOME 'pwsh.exe') -Arguments @('-NoProfile','-File',$clone,'-Modes','retomada_musical') -TimeoutMs 180000
[IO.File]::WriteAllText((Join-Path $work 'execucao.log'),($r.Stdout+[Environment]::NewLine+$r.Stderr),[Text.UTF8Encoding]::new($false))
if($r.ExitCode -ne 0 -or -not $r.Stdout.Contains('EXECUCAO_UNICA_E2E_PASS')){throw ('Falha E2E ISO; examine '+(Join-Path $work 'execucao.log'))}
'ESTADO_STRINGS_E2E_PASS: titulo ISO preservado nas oito variantes de retomada; ferramentas/audio reais, transporte e respostas simulados; Windows'
