#requires -Version 7.0
. (Join-Path $PSScriptRoot 'arquivo_temporario_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'transporte_arquivo_ffmpeg.ps1')

function Invoke-WithFfmpegDownloadedArchive {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$RootDirectory,
        [AllowNull()][object]$Action,
        [Parameter(Mandatory)][uri]$Uri,
        [AllowNull()][object]$ExpectedSize,
        [AllowNull()][object]$ExpectedSha256,
        [ValidateRange(1,300)][int]$TimeoutSeconds = 120,
        [System.Net.Http.HttpMessageHandler]$Handler = $null,
        [Threading.CancellationToken]$CancellationToken = [Threading.CancellationToken]::None
    )

    # Validar RootDirectory antes de qualquer IO
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

    # Validar Action antes de qualquer IO
    if ($null -eq $Action) {
        throw "Action não pode ser nulo."
    }
    if ($Action -isnot [scriptblock]) {
        throw "Action deve ser um scriptblock."
    }

    # Criar contexto exclusivo para preservar valores do wrapper
    $downloadContext = @{
        Uri               = $Uri
        ExpectedSize      = $ExpectedSize
        ExpectedSha256    = $ExpectedSha256
        TimeoutSeconds    = $TimeoutSeconds
        Handler           = $Handler
        CancellationToken = $CancellationToken
    }

    # Consumidor local com nome único para preservar escopo
    $archiveConsumer = $Action

    # Invocar helper que gerencia o arquivo temporário
    Invoke-WithFfmpegArchiveStream -RootDirectory $RootDirectory -Action {
        param([System.IO.Stream]$stream)

        # Adicionar Destination ao contexto
        $downloadContext['Destination'] = $stream

        # Receber fluxo verificado
        $receipt = Receive-FfmpegArchiveStream @downloadContext

        # Flush e rewind
        $stream.Flush()
        $stream.Position = 0

        # Invocar consumidor com stream e receipt
        & $archiveConsumer $stream $receipt
    }
}
