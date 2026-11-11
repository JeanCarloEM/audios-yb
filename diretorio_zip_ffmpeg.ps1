#requires -Version 7.0
. (Join-Path $PSScriptRoot 'rodape_zip_ffmpeg.ps1')

function Get-FfmpegZipDirectory {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$Stream
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

    $originalPosition = $Stream.Position
    try {
        $eocd = Get-FfmpegZipEndRecord -Stream $Stream

        $cdStart = $eocd.directory_offset
        $cdEnd = $cdStart + $eocd.directory_size
        $count = $eocd.entry_count

        if ($count -lt 1) {
            throw "Número de entradas deve ser >= 1."
        }

        $Stream.Position = $cdStart
        $cursor = $cdStart
        $buffer = New-Object byte[] 46

        for ($i = 0; $i -lt $count; $i++) {
            if ($cursor + 46 -gt $cdEnd) {
                throw "Registro central inválido: tamanho insuficiente para cabeçalho fixo."
            }

            $read = 0
            while ($read -lt 46) {
                $chunk = $Stream.Read($buffer, $read, 46 - $read)
                if ($chunk -eq 0) { throw "Fim prematuro no cabecalho central." }
                $read += $chunk
            }
            if ($read -ne 46) {
                throw "Falha ao ler cabeçalho do registro central: leitura parcial."
            }

            $signature = [BitConverter]::ToUInt32($buffer, 0)
            if ($signature -ne 0x02014b50) {
                throw "Assinatura do registro central inválida."
            }

            $nameLen = [BitConverter]::ToUInt16($buffer, 28)
            $extraLen = [BitConverter]::ToUInt16($buffer, 30)
            $commentLen = [BitConverter]::ToUInt16($buffer, 32)
            $diskStart = [BitConverter]::ToUInt16($buffer, 34)
            $localOffset = [BitConverter]::ToUInt32($buffer, 42)

            if ($diskStart -ne 0) {
                throw "Arquivo ZIP com múltiplos discos não é suportado."
            }
            if ($localOffset -eq 0xFFFFFFFF) {
                throw "Offset local inválido (sentinela 0xFFFFFFFF)."
            }
            if ($localOffset -ge $cdStart) {
                throw "Offset local deve ser menor que o início do diretório central."
            }

            $totalLen = 46 + $nameLen + $extraLen + $commentLen
            if ($cursor + $totalLen -gt $cdEnd) {
                throw "Registro central inválido: tamanho total excede limite do diretório."
            }

            $cursor += $totalLen
            $Stream.Position = $cursor
        }

        if ($cursor -ne $cdEnd) {
            throw "Cursor final não coincide com fim do diretório central."
        }

        return @{
            entry_count   = $eocd.entry_count
            directory_offset = $eocd.directory_offset
            directory_size   = $eocd.directory_size
        }
    }
    finally {
        $Stream.Position = $originalPosition
    }
}
