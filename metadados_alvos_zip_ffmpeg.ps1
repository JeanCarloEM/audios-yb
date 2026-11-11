#requires -Version 7.0
. (Join-Path $PSScriptRoot 'diretorio_zip_ffmpeg.ps1')

function Read-FfmpegZipTargetMetadata {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Stream,
        [AllowNull()][object]$ExpectedRootDirectory
    )

    if ($null -eq $Stream) {
        throw "O parâmetro Stream não pode ser nulo."
    }
    if (-not ($Stream -is [IO.Stream])) {
        throw "O parâmetro Stream deve ser um objeto do tipo System.IO.Stream."
    }
    if (-not $Stream.CanRead) {
        throw "O stream deve ser legível (CanRead = true)."
    }
    if (-not $Stream.CanSeek) {
        throw "O stream deve permitir busca (CanSeek = true)."
    }

    if ($ExpectedRootDirectory -isnot [string] -or $ExpectedRootDirectory.Length -gt 180 -or $ExpectedRootDirectory -cnotmatch '\Affmpeg-[A-Za-z0-9][A-Za-z0-9._-]*\z') {
        throw 'ExpectedRootDirectory deve ser um componente ASCII ffmpeg- seguro de ate180 caracteres.'
    }
    $originalPosition = $Stream.Position
    try {
        $zipDirectory = Get-FfmpegZipDirectory -Stream $Stream

        $Stream.Position = 0
        $zipArchive = New-Object IO.Compression.ZipArchive -ArgumentList @($Stream, [IO.Compression.ZipArchiveMode]::Read, $true)

        try {
            $entries = $zipArchive.Entries

            if ($entries.Count -ne $zipDirectory.entry_count) {
                throw "Entries.Count ($($entries.Count)) != descritor entry_count ($($zipDirectory.entry_count))."
            }

            $targetFilenames = @('ffmpeg.exe', 'ffprobe.exe')
            $foundEntries = @{}

            foreach ($entry in $entries) {
                $leafName = $entry.Name
                $leafNameLower = $leafName.ToLowerInvariant()

                if (-not ($targetFilenames -contains $leafNameLower)) {
                    continue
                }

                $fullName = $entry.FullName
                $expectedPath = "$ExpectedRootDirectory/bin/$leafNameLower"

                if ($fullName -cne $expectedPath) {
                    throw "Caminho inválido para ${leafNameLower}: '$fullName' != '$expectedPath'."
                }

                if ($foundEntries.ContainsKey($leafNameLower)) {
                    throw "Duplicado: $leafNameLower."
                }

                $externalAttributes = $entry.ExternalAttributes
                $dosDirectory = ($externalAttributes -band 0x10) -ne 0
                $dosReparse = ($externalAttributes -band 0x400) -ne 0

                if ($dosDirectory -or $dosReparse) {
                    throw "Atributo DOS inválido para ${leafNameLower}: Directory=$dosDirectory, Reparse=$dosReparse."
                }

                $unixAttrs = ($externalAttributes -shr 16) -band 0xF000
                if ($unixAttrs -ne 0 -and $unixAttrs -ne 0x8000) {
                    throw "Atributo Unix inválido para ${leafNameLower}: $unixAttrs (deve ser 0 ou 32768)."
                }

                $size = $entry.Length
                $compressedSize = $entry.CompressedLength

                if ($size -lt 1 -or $size -gt 536870912) {
                    throw "Tamanho inválido para ${leafNameLower}: $size."
                }
                if ($compressedSize -lt 1 -or $compressedSize -gt 536870912) {
                    throw "CompressedLength inválido para ${leafNameLower}: $compressedSize."
                }
                if ($compressedSize -gt $Stream.Length) {
                    throw "CompressedLength ($compressedSize) > Stream.Length ($($Stream.Length)) para ${leafNameLower}."
                }

                $foundEntries[$leafNameLower] = @{
                    path          = $fullName
                    size          = [long]$size
                    compressed_size = [long]$compressedSize
                }
            }

            foreach ($target in $targetFilenames) {
                if (-not $foundEntries.ContainsKey($target)) {
                    throw "Faltando alvo: $target."
                }
            }

            return @{
                ffmpeg  = $foundEntries['ffmpeg.exe']
                ffprobe = $foundEntries['ffprobe.exe']
            }
        }
        finally {
            $zipArchive.Dispose()
        }
    }
    finally {
        $Stream.Position = $originalPosition
    }
}
