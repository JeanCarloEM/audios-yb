function Copy-CheckedFfmpegArchiveStream {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [IO.Stream]$Source,
        [Parameter(Mandatory)]
        [IO.Stream]$Destination,
        [AllowNull()]
        [object]$ExpectedSize,
        [AllowNull()]
        [object]$ExpectedSha256,
        [ValidateRange(1,300)]
        [int]$TimeoutSeconds = 120,
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )

    # Validações iniciais
    if (-not $Source.CanRead) { throw 'Source não é legível' }
    if (-not $Destination.CanWrite) { throw 'Destination não é gravável' }
    if ([object]::ReferenceEquals($Source, $Destination)) { throw 'Source e Destination devem ser instâncias distintas' }

    # Guardas incondicionais para ExpectedSize
    $sizeIsLong = $false
    if ($null -eq $ExpectedSize) { throw 'ExpectedSize obrigatorio' }
    if ($null -ne $ExpectedSize) {
        if ($ExpectedSize -isnot [long]) { throw 'ExpectedSize deve ser [long]' }
        if ($ExpectedSize -lt 1 -or $ExpectedSize -gt 536870912) { throw 'ExpectedSize deve estar entre 1 e 536870912' }
        $sizeIsLong = $true
    }

    # Guardas incondicionais para ExpectedSha256
    $shaIsString = $false
    if ($null -eq $ExpectedSha256) { throw 'ExpectedSha256 obrigatorio' }
    if ($null -ne $ExpectedSha256) {
        if ($ExpectedSha256 -isnot [string]) { throw 'ExpectedSha256 deve ser [string]' }
        if ($ExpectedSha256.Length -ne 64 -or $ExpectedSha256 -cnotmatch '\A[0-9a-f]{64}\z') { throw 'ExpectedSha256 deve ser string de 64 caracteres hexadecimais minúsculos ASCII' }
        $shaIsString = $true
    }

    # Criar CTS combinado (externo + timeout) com uma única CTS
    $ctsCombined = [System.Threading.CancellationTokenSource]::CreateLinkedTokenSource($CancellationToken, [System.Threading.CancellationToken]::None)
    $ctsCombined.CancelAfter([TimeSpan]::FromSeconds($TimeoutSeconds))
    $combinedToken = $ctsCombined.Token

    $hashBuilder = $null
    try {
        $buffer = [byte[]]::new(81920)
        $totalBytesRead = 0L
        $hashBuilder = [Security.Cryptography.IncrementalHash]::CreateHash([Security.Cryptography.HashAlgorithmName]::SHA256)

        while ($true) {
            # Checar cancelamento antes de IO
            $combinedToken.ThrowIfCancellationRequested()

            $readTask = $Source.ReadAsync($buffer, 0, $buffer.Length, $combinedToken)
            $read = $readTask.GetAwaiter().GetResult()
            if ($read -eq 0) { break }

            # Verificar se chunk ultrapassa limite ANTES de escrever
            if ($sizeIsLong -and ($totalBytesRead + $read) -gt $ExpectedSize) {
                throw 'Chunk lido excede tamanho esperado'
            }

            $writeTask = $Destination.WriteAsync($buffer, 0, $read, $combinedToken)
            [void]$writeTask.GetAwaiter().GetResult()

            $hashBuilder.AppendData($buffer, 0, $read) | Out-Null
            $totalBytesRead += $read
        }

        # Verificar tamanho exato
        if ($sizeIsLong -and $totalBytesRead -ne $ExpectedSize) {
            throw "Tamanho esperado $ExpectedSize, mas copiado $totalBytesRead"
        }

        # Verificar hash
        $actualHashBytes = $hashBuilder.GetHashAndReset()
        $actualHash = [BitConverter]::ToString($actualHashBytes).Replace('-', '').ToLowerInvariant()
        if ($shaIsString -and $actualHash -cne $ExpectedSha256) {
            throw "Hash SHA256 esperado $ExpectedSha256, mas calculado $actualHash"
        }

        return @{ size = $totalBytesRead; sha256 = $actualHash }
    }
    finally {
        if ($null -ne $hashBuilder) { $hashBuilder.Dispose() }
        $ctsCombined.Dispose()
    }
}
