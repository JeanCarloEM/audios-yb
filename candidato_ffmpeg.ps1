#requires -Version 7.0
function Invoke-WithFfmpegCandidateFile {
    param(
        [AllowNull()][object]$RootDirectory,
        [AllowNull()][object]$Tool,
        [AllowNull()][object]$Action
    )

    if ($RootDirectory -isnot [string] -or [string]::IsNullOrWhiteSpace($RootDirectory) -or ![IO.Path]::IsPathFullyQualified($RootDirectory)) { throw 'RootDirectory invalido' }
    if ($Tool -isnot [string] -or ($Tool -cne 'ffmpeg' -and $Tool -cne 'ffprobe')) { throw 'Tool invalido' }
    if ($Action -isnot [scriptblock]) { throw 'Action deve ser scriptblock' }
    $directory = Get-Item -LiteralPath $RootDirectory -Force -ErrorAction Stop
    if ($directory -isnot [IO.DirectoryInfo]) { throw 'RootDirectory deve ser diretorio FileSystem existente' }
    $RootDirectory = $directory.FullName

    $candidateName = '.ffmpeg.candidate.' + [guid]::NewGuid().ToString('N') + '.' + $Tool + '.exe'
    $candidatePath = Join-Path $RootDirectory $candidateName
    $stream = $null
    $owned = $false

    try {
        $stream = New-Object IO.FileStream($candidatePath, 'CreateNew', 'ReadWrite', 'None')
        $owned = $true
        & $Action $candidatePath $stream
    }
    finally {
        try { if ($null -ne $stream) { $stream.Dispose() } }
        finally { if ($owned -and [IO.File]::Exists($candidatePath)) { [IO.File]::Delete($candidatePath) } }
    }
}