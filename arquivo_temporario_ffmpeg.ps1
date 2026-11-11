#requires -Version 7.0
function Invoke-WithFfmpegArchiveStream {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$RootDirectory,
        [AllowNull()][object]$Action
    )

    # Validação de RootDirectory
    if ($null -eq $RootDirectory) {
        throw "RootDirectory não pode ser nulo."
    }
    if ($RootDirectory -isnot [string]) {
        throw "RootDirectory deve ser uma string."
    }
    if ([string]::IsNullOrEmpty($RootDirectory)) {
        throw "RootDirectory não pode ser vazio."
    }
    if (-not [System.IO.Path]::IsPathFullyQualified($RootDirectory)) {
        throw "RootDirectory deve ser um caminho absoluto."
    }
    if (-not [System.IO.Directory]::Exists($RootDirectory)) {
        throw "RootDirectory não existe."
    }

    # Validação de Action
    if ($null -eq $Action) {
        throw "Action não pode ser nulo."
    }
    if ($Action -isnot [scriptblock]) {
        throw "Action deve ser um scriptblock."
    }

    $tempPath = $null
    $stream = $null
    try {
        $filename = '.ffmpeg-' + [Guid]::NewGuid().ToString('N') + '.zip.tmp'
        $tempPath = [System.IO.Path]::Combine($RootDirectory, $filename)

        $stream = [System.IO.FileStream]::new($tempPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None, 81920, ([System.IO.FileOptions]::DeleteOnClose -bor [System.IO.FileOptions]::Asynchronous))

        & $Action $stream
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}
