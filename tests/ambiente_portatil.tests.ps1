#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'ambiente_portatil.ps1')
$work=Join-Path $PSScriptRoot ('.runtime-discovery-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $work 'raiz com acento á'
$other=Join-Path $work 'cwd isca'
[void][IO.Directory]::CreateDirectory($root)
[void][IO.Directory]::CreateDirectory($other)
$fake=Join-Path $root 'principal.ps1'
[IO.File]::WriteAllText($fake,'# fixture')
$script:passed=0
function Assert($condition,[string]$message) { if(-not $condition){throw $message}; $script:passed++ }
function MustFail([scriptblock]$action,[string]$message) {
    $failed=$false
    try { $null=& $action } catch { $failed=$true }
    Assert $failed $message
}
# Expectativas independentes: schema CSV de entrada e URL literal preservada.
$columns=@('Ordem','Artista','Musica','Link_YouTube','Tipo_link','Verificacao','Observacoes','Extra')
[IO.File]::WriteAllText((Join-Path $root 'irrelevante.csv'),('Outra,Coluna'+[Environment]::NewLine+'1,2'))
[IO.File]::WriteAllText((Join-Path $other 'isca.csv'),(($columns -join ',')+[Environment]::NewLine+'1,A,M,https://example.invalid/cwd,video,V,O,E'))
$origin=Get-Location
try {
    foreach($cwd in @($repo,$other)){
        Set-Location -LiteralPath $cwd
        $layout=Get-ScriptLayout -ScriptPath $fake
        Assert ($layout.Root -ceq $root) 'Root depende de cwd'
        Assert ($layout.Out -ceq (Join-Path $root 'destino')) 'Destino incorreto'
        Assert ($layout.Control -ceq (Join-Path (Join-Path $root 'destino') '.controle')) 'Controle incorreto'
        Assert ((Resolve-ScriptInput -Path (Join-Path 'dados' '..') -Root $root) -ceq $root) 'Relativo nao canonizado'
        Assert ((Resolve-ScriptInput -Path $fake -Root $other) -ceq $fake) 'Absoluto alterado'
        Assert ((Resolve-ScriptInput -Path 'ausente.csv' -Root $root) -ceq (Join-Path $root 'ausente.csv')) 'Fallback indevido cwd'
        MustFail {Find-ScriptCsv -Root $root} 'CSV isca/irrelevante foi aceito'
    }
    MustFail {Get-ScriptLayout -ScriptPath (Join-Path $root 'ausente.ps1')} 'Script ausente foi aceito'
    MustFail {Resolve-ScriptInput -Path ' ' -Root $root} 'Branco foi aceito'
    MustFail {Find-ScriptCsv -Root $root -Csv 'ausente.csv'} 'CSV explicito ausente aceito'
    foreach($delimiter in @([char]',',[char]';',[char]9)){
        $case=Join-Path $root ('caso-'+[int]$delimiter)
        [void][IO.Directory]::CreateDirectory($case)
        [IO.File]::WriteAllText((Join-Path $case 'irrelevante.csv'),('Outra,Coluna'+[Environment]::NewLine+'1,2'))
        $csv=Join-Path $case 'canônico.csv'
        $url='https://www.youtube.com/watch?v=CSVsource01'
        $row=@('1','Artista','Musica',$url,'video','V','O','E')
        foreach($bom in @($false,$true)){
            [IO.File]::WriteAllText($csv,(($columns -join $delimiter)+[Environment]::NewLine+($row -join $delimiter)),[Text.UTF8Encoding]::new($bom))
            $before=(Get-FileHash -LiteralPath $csv).Hash
            Assert ((Find-ScriptCsv -Root $case) -ceq $csv) 'Descoberta unica/delimitador/BOM incorretos'
            Assert ((Find-ScriptCsv -Root $case -Csv 'canônico.csv') -ceq $csv) 'CSV explicito relativo incorreto'
            Assert ((Import-Csv -LiteralPath $csv -Delimiter $delimiter).Link_YouTube -ceq $url) 'URL CSV alterada'
            Assert ((Get-FileHash -LiteralPath $csv).Hash -ceq $before) 'Descoberta escreveu CSV'
        }
        [IO.File]::Copy($csv,(Join-Path $case 'segundo.csv'))
        MustFail {Find-ScriptCsv -Root $case} 'Ambiguidade nao foi rejeitada'
        Assert ((Find-ScriptCsv -Root $case -Csv 'canônico.csv') -ceq $csv) 'Explicito nao resolve ambiguidade'
    }
    Assert (-not (Test-Path -LiteralPath (Join-Path $root 'destino'))) 'Descoberta escreveu destino'
} finally { Set-Location -LiteralPath $origin }
Write-Output ("AMBIENTE_PORTATIL_PASS checks="+$script:passed+"; OS="+[Runtime.InteropServices.RuntimeInformation]::OSDescription+"; PS="+$PSVersionTable.PSVersion+"; sem navegador/rede; links nao exercitados")