#requires -Version 7.0
function Get-FfmpegZipEndRecord {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Stream
    )

    # Validação do stream
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
    if ($Stream.Length -lt 22 -or $Stream.Length -gt 536870912) {
        throw "O tamanho do arquivo deve estar entre 22 e 536870912 bytes."
    }

    $originalPosition = $Stream.Position
    try {
        # Calcular tamanho da cauda a ler (mínimo 22, máximo 65557)
        $tailSize = [Math]::Min($Stream.Length, 65557)
        $readFrom = $Stream.Length - $tailSize
        $Stream.Position = $readFrom

        $buffer = New-Object byte[] $tailSize
        $totalRead = 0
        while ($totalRead -lt $tailSize) {
            $read = $Stream.Read($buffer, $totalRead, $tailSize - $totalRead)
            if ($read -eq 0) {
                throw "Falha ao ler cauda do arquivo: leitura parcial ou prematura."
            }
            $totalRead += $read
        }

        # Procurar assinatura EOCD de trás para frente
        $eocdSignature = 0x06054b50
        $pos = $tailSize - 22
        while ($pos -ge 0) {
            if ([BitConverter]::ToUInt32($buffer, $pos) -eq $eocdSignature) {
                $commentLen = [BitConverter]::ToUInt16($buffer, $pos + 20)
                $expectedEndPos = $pos + 22 + $commentLen
                if ($expectedEndPos -eq $tailSize) {
                    # Campos EOCD
                    $diskNum = [BitConverter]::ToUInt16($buffer, $pos + 4)
                    $diskDirNum = [BitConverter]::ToUInt16($buffer, $pos + 6)
                    $entryCount = [BitConverter]::ToUInt16($buffer, $pos + 8)
                    $entryCountTotal = [BitConverter]::ToUInt16($buffer, $pos + 10)
                    $dirSize = [BitConverter]::ToUInt32($buffer, $pos + 12)
                    $dirOffset = [BitConverter]::ToUInt32($buffer, $pos + 16)

                    # Validações de perfil restrito
                    if ($diskNum -ne 0 -or $diskDirNum -ne 0) {
                        throw "Arquivo ZIP com múltiplos discos não é suportado."
                    }
                    if ($entryCount -eq 0xFFFF -or $entryCountTotal -eq 0xFFFF -or $dirSize -eq 0xFFFFFFFF -or $dirOffset -eq 0xFFFFFFFF) {
                        throw "Arquivo ZIP64 não é suportado."
                    }
                    if ($entryCount -ne $entryCountTotal -or $entryCount -lt 1 -or $entryCount -gt 4096) {
                        throw "Número de entradas inválido: deve estar entre 1 e 4096."
                    }
                    if ($dirSize -lt 46 -or $dirSize -gt 8388608) {
                        throw "Tamanho do diretório inválido: deve estar entre 46 e 8388608 bytes."
                    }
                    if (([long]$dirOffset + [long]$dirSize) -ne ([long]$readFrom + [long]$pos)) {
                        throw "Offset do diretório e tamanho não coincidem com posição do EOCD."
                    }

                    return @{
                        entry_count   = [int]$entryCount
                        directory_offset = [long]$dirOffset
                        directory_size   = [long]$dirSize
                    }
                }
            }
            $pos--
        }
        throw "Assinatura EOCD não encontrada no final do arquivo."
    }
    finally {
        $Stream.Position = $originalPosition
    }
}
