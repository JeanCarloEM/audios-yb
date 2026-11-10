function Invoke-YtdlpCandidateFile {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][scriptblock]$Action
    )

    # candidate-literal-root-v1: resolve pelo contexto PowerShell, sem curingas.
    if ([string]::IsNullOrWhiteSpace($Root)) { throw 'Root invalido' }
    $directory = Get-Item -LiteralPath $Root -Force -ErrorAction Stop
    if ($directory -isnot [IO.DirectoryInfo]) { throw 'Root deve ser diretorio FileSystem existente' }
    $Root = $directory.FullName

    $candidateName = '.yt-dlp.candidate.' + [guid]::NewGuid().ToString('N') + '.exe'
    $candidatePath = Join-Path $Root $candidateName
    $stream = $null
    $owned = $false

    try {
        $stream = New-Object IO.FileStream($candidatePath, 'CreateNew', 'ReadWrite', 'None')
        $owned = $true
        & $Action $candidatePath $stream
    }
    finally {
        if ($null -ne $stream) {
            $stream.Close()
        }
        if ($owned -and [IO.File]::Exists($candidatePath)) {
            Remove-Item -LiteralPath $candidatePath -Force
        }
    }
}
