#requires -Version 7.0
function Invoke-WithFfmpegCandidateReadLock {
    param(
        [AllowNull()][object]$Path,
        [AllowNull()][object]$ExpectedSize,
        [AllowNull()][object]$ExpectedSha256,
        [AllowNull()][object]$Action
    )

    if ($Path -isnot [string] -or [string]::IsNullOrWhiteSpace($Path)) { throw 'Path não pode ser branco' }
    if (![IO.Path]::IsPathFullyQualified($Path)) { throw 'Path deve ser absoluteFullyQualified' }
    if ($ExpectedSize -isnot [long] -or $ExpectedSize -lt 1 -or $ExpectedSize -gt 536870912) { throw 'ExpectedSize deve estar entre 1 e 536870912' }
    if ($ExpectedSha256 -isnot [string] -or $ExpectedSha256 -cnotmatch '\A[a-f0-9]{64}\z') { throw 'ExpectedSha256 deve ser string64hex minúscula' }
    if ($Action -isnot [scriptblock]) { throw 'Action não pode ser nulo' }

    $item = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item -isnot [IO.FileInfo] -or -not $item.Exists) { throw "Arquivo não encontrado: $Path" }

    $stream = $null; $hasher = $null
    try {
        $stream = $item.Open([IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        if ($stream.Length -ne $ExpectedSize) { throw "Tamanho divergente: esperado $ExpectedSize, obtido $($stream.Length)" }

        $hasher = [System.Security.Cryptography.SHA256]::Create()
        $bytes = $hasher.ComputeHash($stream)
        $actualHash = [System.BitConverter]::ToString($bytes) -replace '-', '' | ForEach-Object { $_.ToLowerInvariant() }
        if ($actualHash -cne $ExpectedSha256) { throw "SHA256 divergente: esperado $ExpectedSha256, obtido $actualHash" }

        $stream.Position = 0
        $result = & $Action $stream $item.FullName
        return $result
    }
    finally {
        try { if ($null -ne $hasher) { $hasher.Dispose() } }
        finally { if ($null -ne $stream) { $stream.Dispose() } }
    }
}