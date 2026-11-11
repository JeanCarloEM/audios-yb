#requires -Version 7.0
. (Join-Path $PSScriptRoot 'uris_release_ffmpeg.ps1')
function Get-FfmpegReleaseDocumentBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uri]$Uri,
        [ValidateRange(1,2097152)]
        [int]$MaxBytes = 1048576,
        [ValidateRange(1,120)]
        [int]$TimeoutSeconds = 30,
        [System.Net.Http.HttpMessageHandler]$Handler = $null
    )

    $cts = $null
    $client = $null
    $request = $null
    $response = $null
    $stream = $null
    $memoryStream = $null

    try {
        if (-not (Test-FfmpegRequestUri -Uri $Uri)) { throw 'URI inicial invalida' }
        $isApi = $Uri.DnsSafeHost -ceq 'api.github.com'
        if (-not $isApi -and -not $Uri.AbsolutePath.EndsWith('/checksums.sha256',[StringComparison]::Ordinal)) {
            throw 'Somente documentos; ZIP exige transporte streaming'
        }

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

            $cts = New-Object System.Threading.CancellationTokenSource
            $cts.CancelAfter([System.TimeSpan]::FromSeconds($TimeoutSeconds))

            $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $Uri)
            $request.Headers.UserAgent.ParseAdd('ffmpeg-release-downloader/1.0')

            $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cts.Token).GetAwaiter().GetResult()



            $currentUri = $Uri
            $redirectCount = 0

            while ([int]$response.StatusCode -in @(301,302,303,307,308)) {
                if ($isApi) { throw 'API de metadata nao pode redirecionar' }
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

                $response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cts.Token).GetAwaiter().GetResult()


            }

            if ($response.StatusCode -ne [System.Net.HttpStatusCode]::OK) { throw 'Status diferente de 200' }
            # Validar Content-Length
            $contentLength = $response.Content.Headers.ContentLength
            if ($contentLength -gt $MaxBytes) {
                throw 'Content-Length maior que MaxBytes'
            }

            # Ler corpo
            $stream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $memoryStream = New-Object System.IO.MemoryStream

            $buffer = New-Object byte[](81920)
            $totalRead = 0

            while ($true) {
                $cts.Token.ThrowIfCancellationRequested()
                $read = $stream.ReadAsync($buffer, 0, $buffer.Length, $cts.Token).GetAwaiter().GetResult()
                if ($read -eq 0) { break }

                if ($totalRead + $read -gt $MaxBytes) {
                    throw 'Corpo excede MaxBytes'
                }

                $memoryStream.Write($buffer, 0, $read)
                $totalRead += $read
            }

            return ,$memoryStream.ToArray()
        } finally {
            # Liberar recursos
            if ($null -ne $response) { $response.Dispose() }
            if ($null -ne $request) { $request.Dispose() }
            if ($null -ne $stream) { $stream.Dispose() }
            if ($null -ne $memoryStream) { $memoryStream.Dispose() }
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
