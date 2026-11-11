#requires -Version 7.0
function New-DirectoryWriteProbeName {
    '.audios-yb-write.' + [guid]::NewGuid().ToString('N') + '.tmp'
}

function Invoke-DirectoryWriteProbe {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Root)
    # Prova apenas o ciclo de arquivo proprio neste instante; nao direitos sobre
    # arquivos existentes nem necessidade de elevacao.
    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'Root invalido' }
    $directory = Get-Item -LiteralPath $Root -Force -ErrorAction Stop
    if ($directory -isnot [IO.DirectoryInfo]) { throw 'Root deve ser diretorio FileSystem existente' }
    $probePath = Join-Path -Path $directory.FullName -ChildPath (New-DirectoryWriteProbeName)
    $stream = $null
    $owned = $false
    try {
        $stream = [IO.FileStream]::new($probePath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $owned = $true
        $stream.WriteByte(1)
        $stream.Flush($true)
    }
    finally {
        try {
            if ($null -ne $stream) { $stream.Dispose() }
        }
        finally {
            if ($owned) { [IO.File]::Delete($probePath) }
        }
    }
    return @{directory=$directory.FullName; create_write_delete_verified=$true}
}
