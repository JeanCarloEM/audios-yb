#requires -Version 7.0
function Get-YtdlpReleaseBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uri]$Uri,
        [ValidateRange(1,67108864)]
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
        # https-contract-repaired-v1: origem inicial fechada e tag/asset literais.
        $uriStr = $Uri.AbsoluteUri
        $isApi = [string]::Equals($uriStr,'https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest',[StringComparison]::Ordinal)
        $assetMatch = [regex]::Match($uriStr,'\Ahttps://github\.com/yt-dlp/yt-dlp/releases/download/([A-Za-z0-9][A-Za-z0-9._-]{0,127})/(SHA2-256SUMS|yt-dlp\.exe|yt-dlp_x86\.exe|yt-dlp_arm64\.exe)\z')
        if (-not $isApi -and -not $assetMatch.Success) { throw 'URI inicial invalida' }
        if ($assetMatch.Success -and $assetMatch.Groups[1].Value.ToLowerInvariant() -in @('latest','stable','nightly','master')) { throw 'Canal mutavel nao e tag de release' }

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
            $request.Headers.UserAgent.ParseAdd('yt-dlp-release-downloader/1.0')

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

                # Validar redirect
                if ($nextUri.Scheme -ne 'https' -or $nextUri.Port -ne 443 -or $nextUri.UserInfo -or $nextUri.Fragment) {
                    throw 'Redirect inseguro'
                }

                $nextHostLower = $nextUri.Host.ToLowerInvariant()
                if ($nextHostLower -ne 'release-assets.githubusercontent.com') {
                    throw 'Redirect para host não autorizado'
                }

                $redirectCount++
                if ($redirectCount -gt 4) {
                    throw 'Máximo de 4 redirects excedido'
                }

                $currentUri = $nextUri

                $response.Dispose()
                $request.Dispose()

                $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, $currentUri)
                $request.Headers.UserAgent.ParseAdd('yt-dlp-release-downloader/1.0')

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
