#requires -Version 7.0
function Get-CanonicalAudioSearchQuery([object]$SourceUrl = $null) {
    if ($SourceUrl -isnot [string]) { throw [ArgumentException]::new('SourceUrl deve ser string') }
    $Text = $SourceUrl
    $uri = $null
    if (-not [uri]::TryCreate($Text, [UriKind]::Absolute, [ref]$uri)) { throw [ArgumentException]::new('URL sem sintaxe valida') }
    $hostName = $uri.Host.ToLowerInvariant()
    if ($uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Port -ne 443 -or
        $hostName -notin @('www.youtube.com', 'youtube.com', 'm.youtube.com', 'music.youtube.com')) {
        throw [ArgumentException]::new('URL rejeitada: exigir HTTPS em dominio oficial YouTube, sem credenciais/porta alternativa')
    }
    $params = @{}
    foreach ($fragment in $uri.Query.TrimStart('?').Split('&')) {
        if ($fragment -eq '') { continue }
        $parts = @($fragment -split '=', 2)
        $key = [Net.WebUtility]::UrlDecode($parts[0])
        if ($params.ContainsKey($key)) { throw [ArgumentException]::new('Parametro de URL duplicado: ' + $key) }
        $params[$key] = if ($parts.Count -eq 2) { [Net.WebUtility]::UrlDecode($parts[1]) } else { '' }
    }
    if ($uri.AbsolutePath -eq '/results' -and $params.ContainsKey('search_query')) {
        $q = [string]$params['search_query']
        if ($q.Length -lt 3 -or $q.Length -gt 220 -or $q -match '[\x00-\x1F]') { throw [ArgumentException]::new('Termo de pesquisa invalido/abusivo') }
        return $q
    }
    throw [ArgumentException]::new('URL deve ser pagina de busca YouTube /results com search_query')
}
