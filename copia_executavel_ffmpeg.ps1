function Copy-FfmpegExecutableStream {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [IO.Stream]$SourceStream,
        [Parameter(Mandatory)]
        [IO.Stream]$DestinationStream,
        [AllowNull()]
        [object]$ExpectedSize,
        [ValidateRange(1,300)]
        [int16]$TimeoutSeconds = 120,
        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None
    )

    # Validações iniciais
    if (-not $SourceStream.CanRead) { throw 'SourceStream não é legível' }
    if (-not $DestinationStream.CanWrite) { throw 'DestinationStream não é gravável' }
    if ([object]::ReferenceEquals($SourceStream, $DestinationStream)) { throw 'SourceStream e DestinationStream devem ser instâncias distintas' }

    # Guardas incondicionais para ExpectedSize
    if ($null -eq $ExpectedSize) { throw 'ExpectedSize obrigatorio' }
    if ($ExpectedSize -isnot [long]) { throw 'ExpectedSize deve ser [long]' }
    if ($ExpectedSize -lt 1 -or $ExpectedSize -gt 536870912) { throw 'ExpectedSize deve estar entre 1 e 536870912' }

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

            $readTask = $SourceStream.ReadAsync($buffer, 0, $buffer.Length, $combinedToken)
            $read = $readTask.GetAwaiter().GetResult()
            if ($read -eq 0) { break }

            # Verificar se chunk ultrapassa limite ANTES de escrever
            if (($totalBytesRead + $read) -gt $ExpectedSize) {
                throw 'Chunk lido excede tamanho esperado'
            }

            $writeTask = $DestinationStream.WriteAsync($buffer, 0, $read, $combinedToken)
            [void]$writeTask.GetAwaiter().GetResult()

            $hashBuilder.AppendData($buffer, 0, $read) | Out-Null
            $totalBytesRead += $read
        }

        # Verificar tamanho exato
        if ($totalBytesRead -ne $ExpectedSize) {
            throw "Tamanho esperado $ExpectedSize, mas copiado $totalBytesRead"
        }

        # Retornar apenas hashtable com size e sha256
        $actualHashBytes = $hashBuilder.GetHashAndReset()
        $actualHash = [BitConverter]::ToString($actualHashBytes).Replace('-', '').ToLowerInvariant()
        return @{ size = $totalBytesRead; sha256 = $actualHash }
    }
    finally {
        if ($null -ne $hashBuilder) { $hashBuilder.Dispose() }
        $ctsCombined.Dispose()
    }
}
