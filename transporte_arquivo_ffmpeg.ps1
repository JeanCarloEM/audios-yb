#requires -Version 7.0
. (Join-Path $PSScriptRoot 'validacao_transferencia_ffmpeg.ps1')
. (Join-Path $PSScriptRoot 'copia_stream_ffmpeg.ps1')
function Receive-FfmpegArchiveStream {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][uri]$Uri,
        [AllowNull()][IO.Stream]$Destination,
        [AllowNull()][object]$ExpectedSize,
        [AllowNull()][object]$ExpectedSha256,
        [ValidateRange(1,300)][int]$TimeoutSeconds = 120,
        [System.Net.Http.HttpMessageHandler]$Handler = $null,
        [Threading.CancellationToken]$CancellationToken = [Threading.CancellationToken]::None
    )

    $cts = $null
    $client = $null
    $request = $null
    $response = $null
    $stream = $null


    try {
        if (-not (Test-FfmpegArchiveTransfer -Uri $Uri -Destination $Destination -ExpectedSize $ExpectedSize -ExpectedSha256 $ExpectedSha256)) { throw [ArgumentException]::new('Parametros de transferencia invalidos') }

        # Criar cliente e handler
        $ownHandler = $null
        try {
            if ($Handler) {
                $ownHandler = $Handler
                if ($Handler -is [System.Net.Http.HttpClientHandler]) {
                    $Handler.AllowAutoRedirect = $false
                    $Handler.UseCookies = $false
                    $Handler.UseDefaultCredentials = $false
                }
            } else {
                $ownHandler = New-Object System.Net.Http.HttpClientHandler
                $ownHandler.AllowAutoRedirect = $false
                $ownHandler.UseCookies = $false
                $ownHandler.UseDefaultCredentials = $false
            }

            $client = [System.Net.Http.HttpClient]::new($ownHandler,($null -eq $Handler))
            $client.Timeout = [System.Threading.Timeout]::InfiniteTimeSpan

            $cts = [Threading.CancellationTokenSource]::CreateLinkedTokenSource($CancellationToken,[Threading.CancellationToken]::None)
            $cts.CancelAfter([System.TimeSpan]::FromSeconds($TimeoutSeconds))

            $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $Uri)
            $request.Headers.UserAgent.ParseAdd('ffmpeg-release-downloader/1.0')

            $cts.Token.ThrowIfCancellationRequested()
            $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cts.Token).GetAwaiter().GetResult()



            $currentUri = $Uri
            $redirectCount = 0

            while ([int]$response.StatusCode -in @(301,302,303,307,308)) {

                $location = $response.Headers.Location
                if (-not $location) {
                    throw 'Redirect sem Location'
                }

                # Resolver Location relativa
                if ($location.IsAbsoluteUri) {
                    $nextUri = $location
                } else {
                    $nextUri = New-Object System.Uri($currentUri, $location)
                }

                if (-not (Test-FfmpegRequestUri -Uri $nextUri -Redirect)) {
                    throw 'Redirect inseguro ou host nao autorizado'
                }

                $redirectCount++
                if ($redirectCount -gt 4) {
                    throw 'Máximo de 4 redirects excedido'
                }

                $currentUri = $nextUri

                $response.Dispose()
                $request.Dispose()

                $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $currentUri)
                $request.Headers.UserAgent.ParseAdd('ffmpeg-release-downloader/1.0')

                $cts.Token.ThrowIfCancellationRequested()
            $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cts.Token).GetAwaiter().GetResult()


            }

            if ($response.StatusCode -ne [System.Net.HttpStatusCode]::OK) { throw 'Status diferente de 200' }
            $contentLength = $response.Content.Headers.ContentLength
            if ($null -ne $contentLength -and $contentLength -ne $ExpectedSize) { throw 'Content-Length diverge do tamanho esperado' }
            $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            return Copy-CheckedFfmpegArchiveStream -Source $stream -Destination $Destination -ExpectedSize $ExpectedSize -ExpectedSha256 $ExpectedSha256 -TimeoutSeconds $TimeoutSeconds -CancellationToken $cts.Token
        } finally {
            # Liberar recursos
            if ($null -ne $response) { $response.Dispose() }
            if ($null -ne $request) { $request.Dispose() }
            if ($null -ne $stream) { $stream.Dispose() }

            if ($null -ne $cts) { $cts.Cancel() }
            if ($null -ne $cts) { $cts.Dispose() }
            if ($null -eq $client -and $null -ne $ownHandler -and $null -eq $Handler) {
                $ownHandler.Dispose()
            }
        }
    } finally {
        if ($null -ne $client) { $client.Dispose() }
    }
}
