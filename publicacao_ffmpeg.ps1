#requires -Version 7.0
. (Join-Path $PSScriptRoot 'copia_stream_ffmpeg.ps1')

function Publish-FfmpegExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, Position=0)]
        [AllowNull()][object]$RootDirectory,
        [Parameter(Mandatory=$true, Position=1)]
        [AllowNull()][object]$SourceStream,
        [Parameter(Mandatory=$true, Position=2)]
        [AllowNull()][object]$Tool,
        [Parameter(Mandatory=$true, Position=3)]
        [AllowNull()][object]$ExpectedSize,
        [Parameter(Mandatory=$true, Position=4)]
        [AllowNull()][object]$ExpectedSha256
    )

    # Guardas iniciais
    if ($RootDirectory -isnot [string]) { throw [ArgumentException]::new('RootDirectory deve ser string.', 'RootDirectory') }
    if ([string]::IsNullOrWhiteSpace($RootDirectory)) {
        throw [ArgumentException]::new("RootDirectory não pode ser nulo, vazio ou em branco.", 'RootDirectory')
    }
    if (-not [IO.Path]::IsPathFullyQualified($RootDirectory)) {
        throw [ArgumentException]::new("RootDirectory deve ser um caminho totalmente qualificado.", 'RootDirectory')
    }
    $rootItem = Get-Item -LiteralPath $RootDirectory -ErrorAction Stop
    if ($rootItem -isnot [IO.DirectoryInfo]) {
        throw [ArgumentException]::new("RootDirectory deve ser um diretório válido.", 'RootDirectory')
    }
    $RootDirectory = $rootItem.FullName

    if ($null -eq $SourceStream -or $SourceStream -isnot [IO.Stream]) {
        throw [ArgumentException]::new("SourceStream deve ser uma instância de System.IO.Stream.", 'SourceStream')
    }
    if (-not $SourceStream.CanRead) {
        throw [ArgumentException]::new("SourceStream deve ser legível.", 'SourceStream')
    }
    if (-not $SourceStream.CanSeek) {
        throw [ArgumentException]::new("SourceStream deve permitir seek.", 'SourceStream')
    }
    if ($SourceStream.CanWrite) {
        throw [ArgumentException]::new("SourceStream não deve ser gravável.", 'SourceStream')
    }

    if ($null -eq $Tool -or $Tool -isnot [string]) {
        throw [ArgumentException]::new("Tool deve ser uma string não nula.", 'Tool')
    }
    if ($Tool -cnotin @('ffmpeg', 'ffprobe')) {
        throw [ArgumentException]::new("Tool deve ser 'ffmpeg' ou 'ffprobe'.", 'Tool')
    }

    if ($null -eq $ExpectedSize -or $ExpectedSize -isnot [long]) {
        throw [ArgumentException]::new("ExpectedSize deve ser uma instância de [long].", 'ExpectedSize')
    }
    if ($ExpectedSize -lt 1 -or $ExpectedSize -gt 536870912) {
        throw [ArgumentOutOfRangeException]::new('ExpectedSize', "Deve estar entre 1 e 536870912.")
    }

    if ($null -eq $ExpectedSha256 -or $ExpectedSha256 -isnot [string]) {
        throw [ArgumentException]::new("ExpectedSha256 deve ser uma string não nula.", 'ExpectedSha256')
    }
    if ($ExpectedSha256 -cnotmatch '\A[a-f0-9]{64}\z') {
        throw [ArgumentException]::new("ExpectedSha256 deve ser string de 64 caracteres hexadecimais minúsculos.", 'ExpectedSha256')
    }

    if ($SourceStream.Length -ne $ExpectedSize) {
        throw [ArgumentException]::new("SourceStream.Length ($($SourceStream.Length)) deve ser igual a ExpectedSize ($ExpectedSize).", 'SourceStream')
    }

    $targetPath = Join-Path $RootDirectory ($Tool + '.exe')
    $originalPosition = $SourceStream.Position

    try {
        # Se destino existe
        if ([IO.File]::Exists($targetPath)) {
            $existingStream = $null
            try {
                $existingStream = [IO.File]::OpenRead($targetPath)
                if ($existingStream.Length -ne $ExpectedSize) {
                    throw [System.IO.IOException]::new("Destino divergente: tamanho $([IO.File]::GetLength($targetPath)) != $ExpectedSize")
                }
                $actualHash = Get-FileHash -LiteralPath $targetPath -Algorithm SHA256
                $actualHashLower = $actualHash.Hash.ToLowerInvariant()
                if ($actualHashLower -cne $ExpectedSha256) {
                    throw [System.IO.IOException]::new("Destino divergente: hash $actualHashLower != $ExpectedSha256")
                }
                return @{
                    status = 'existing'
                    target_path = [IO.Path]::GetFullPath($targetPath)
                    size = $existingStream.Length
                    sha256 = $actualHashLower
                }
            } finally {
                if ($null -ne $existingStream) { $existingStream.Dispose() }
            }
        } elseif ([IO.Directory]::Exists($targetPath)) {
            throw [System.IO.IOException]::new("Destino é diretório: $targetPath")
        }

        # Destino ausente: criar temporário
        $tempPath = $null
        $tempStream = $null
        $tempOwned = $false
        $hasher = $null

        try {
            $tempPath = Join-Path $RootDirectory ('.ffmpeg.publish.' + [guid]::NewGuid().ToString('N') + '.' + $Tool + '.tmp')

            $SourceStream.Position = 0
            $tempStream = [IO.File]::Open($tempPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            $tempOwned = $true

            $hasher = [Security.Cryptography.SHA256]::Create()

            $result = Copy-CheckedFfmpegArchiveStream -Source $SourceStream -Destination $tempStream -ExpectedSize $ExpectedSize -ExpectedSha256 $ExpectedSha256

            $tempStream.Flush($true)
            $tempStream.Position = 0

            $tempHashBytes = $hasher.ComputeHash($tempStream)
            $tempHashStr = [BitConverter]::ToString($tempHashBytes).Replace('-', '').ToLowerInvariant()

            if ($tempHashStr -cne $ExpectedSha256) {
                throw [System.IO.IOException]::new("Hash do temporário diverge do esperado.")
            }

            if ($tempStream.Length -ne $ExpectedSize) {
                throw [System.IO.IOException]::new("Tamanho do temporário diverge do esperado.")
            }
        } catch {
            if ($null -ne $tempStream) { $tempStream.Dispose() }
            if ($tempOwned -and $null -ne $tempPath -and [IO.File]::Exists($tempPath)) {
                try { [IO.File]::Delete($tempPath) } catch { }
            }
            throw
        } finally {
            if ($null -ne $hasher) { $hasher.Dispose() }
        }

        if ($null -ne $tempStream) { $tempStream.Dispose() }

        try {
            [IO.File]::Move($tempPath, $targetPath)
        } catch {
            if ($tempOwned -and $null -ne $tempPath -and [IO.File]::Exists($tempPath)) {
                try { [IO.File]::Delete($tempPath) } catch { }
            }
            throw
        }

        return @{
            status = 'published'
            target_path = [IO.Path]::GetFullPath($targetPath)
            size = $ExpectedSize
            sha256 = $ExpectedSha256
        }
    } finally {
        $SourceStream.Position = $originalPosition
    }
}
