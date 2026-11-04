function Get-YtdlpAuthArgs([string]$CookiesArquivo, [string]$CookiesNavegador) {
    $authArguments = @()

    if ($CookiesArquivo -and $CookiesNavegador) {
        throw "Especifique apenas um dos parâmetros: CookiesArquivo ou CookiesNavegador."
    }

    if ($CookiesArquivo) {
        $caminho = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CookiesArquivo)
        $caminhoCanonico = [System.IO.Path]::GetFullPath($caminho)
        if (-not (Test-Path -LiteralPath $caminhoCanonico -PathType Leaf)) {
            throw "Arquivo de cookies não encontrado: $caminhoCanonico"
        }
        $primeiraLinha = Get-Content -LiteralPath $caminhoCanonico -TotalCount 1
        if (-not ($primeiraLinha -match '^# (?:Netscape HTTP|HTTP) Cookie File$')) {
            throw "Formato inválido no arquivo de cookies."
        }
        $authArguments += '--cookies', $caminhoCanonico
    }

    if ($CookiesNavegador) {
        $parts = $CookiesNavegador -split ':', 2
        $nomeNavegador = $parts[0].ToLowerInvariant()
        $perfisValidos = @('brave', 'chrome', 'chromium', 'edge', 'firefox', 'opera', 'vivaldi', 'whale')
        if (-not ($perfisValidos -contains $nomeNavegador)) {
            throw "Navegador inválido: $nomeNavegador. Valores aceitos: $($perfisValidos -join ', ')."
        }
        if ($parts.Count -eq 2 -and [string]::IsNullOrWhiteSpace($parts[1])) {
            throw "Perfil inválido: valor vazio após ':'."
        }
        $descriptor = $CookiesNavegador
        $authArguments += '--cookies-from-browser', $descriptor
    }

    return $authArguments
}
