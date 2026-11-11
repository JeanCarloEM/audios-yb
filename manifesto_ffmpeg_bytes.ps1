#requires -Version 7.0
function ConvertFrom-CheckedFfmpegManifest {
    [CmdletBinding()]
    param([AllowNull()][object]$Bytes,[AllowNull()][object]$ExpectedSize,[AllowNull()][object]$ExpectedSha256)
    if ($Bytes -isnot [byte[]] -or $Bytes.Length -lt 1 -or $Bytes.Length -gt 1048576) {
        throw [ArgumentException]::new('Bytes deve ser byte[] de 1 a 1048576 bytes')
    }
    if ($ExpectedSize -isnot [long] -or $ExpectedSize -lt 1 -or $ExpectedSize -gt 1048576) {
        throw [ArgumentException]::new('ExpectedSize deve ser Int64 de 1 a 1048576')
    }
    if ($ExpectedSha256 -isnot [string] -or $ExpectedSha256 -cnotmatch '\A[a-f0-9]{64}\z') {
        throw [ArgumentException]::new('ExpectedSha256 deve ser SHA256 hexadecimal minusculo')
    }

    if ($null -eq $Bytes) {
        throw [ArgumentException]::new('Bytes não pode ser nulo')
    }

    if ($Bytes.Length -ne $ExpectedSize) {
        throw [ArgumentException]::new('Tamanho de Bytes não confere com ExpectedSize')
    }

    if (-not ($ExpectedSha256 -match '^[a-f0-9]{64}$')) {
        throw [ArgumentException]::new('ExpectedSha256 deve ser uma string hexadecimal de 64 caracteres')
    }

    $sha256Hash = $null
    try {
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hashBytes = $sha256.ComputeHash($Bytes)
        } finally {
            $sha256.Dispose()
        }
        $sha256Hash = [BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
    } catch {
        throw [ArgumentException]::new('Falha ao calcular SHA256', $_.Exception)
    }

    if ($sha256Hash -cne $ExpectedSha256) {
        throw [ArgumentException]::new('Hash SHA256 não confere com ExpectedSha256')
    }

    try {
        $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
        $text = $utf8.GetString($Bytes)
    } catch [System.Text.DecoderFallbackException] {
        throw
    }

    return @{
        text  = $text
        sha256 = $sha256Hash
    }
}
