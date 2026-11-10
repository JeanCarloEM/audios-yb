function Invoke-YtdlpVerifiedCandidate {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedSha256,
        [Parameter(Mandatory)][string]$ExpectedVersion,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Path não pode ser branco' }
    if ([string]::IsNullOrWhiteSpace($ExpectedSha256)) { throw 'ExpectedSha256 não pode ser branco' }
    if ($ExpectedSha256 -notmatch '^[a-f0-9]{64}$') { throw 'ExpectedSha256 deve ser string64hex minúscula' }
    if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) { throw 'ExpectedVersion não pode ser branco' }
    if ($null -eq $Action) { throw 'Action não pode ser nulo' }

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if (-not $item.Exists) { throw "Arquivo não encontrado: $Path" }

    $stream = $null; $hasher = $null
    try {
        $stream = $item.Open([IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        $bytes = $hasher.ComputeHash($stream)
        $actualHash = [System.BitConverter]::ToString($bytes) -replace '-', '' | ForEach-Object { $_.ToLowerInvariant() }
        if ($actualHash -cne $ExpectedSha256) { throw "SHA256 divergente: esperado $ExpectedSha256, obtido $actualHash" }

        $result = Invoke-Ytdlp -Executable $item.FullName -Arguments @('--ignore-config','--no-plugin-dirs','--version') -TimeoutSeconds 15
        if ($result.timeout -eq $true -or $result.code -ne 0 -or $result.out.Trim() -cne $ExpectedVersion) {
            throw "Invocação inválida: code=$($result.code), timeout=$($result.timeout), out='$($result.out.Trim())'"
        }

        & $Action $result.out.Trim() $item.FullName
    }
    finally {
        if ($null -ne $hasher) { $hasher.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}
