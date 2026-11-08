#requires -Version 7.0
function New-PublicationReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[A-Za-z0-9_-]{11}$', Options = 'None')]
        [string]$VideoId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[a-f0-9]{64}$', Options = 'None')]
        [string]$RecordKey,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern('^[a-f0-9]{64}$', Options = 'None')]
        [string]$IntentSha256
    )

    # Calcular SHA256 do VideoId original (preservar case)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($VideoId)
        $hashBytes = $sha256.ComputeHash($bytes)
        $hashHex = [System.BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }

    $leaf = $hashHex + '.json'

    return @{
        versao       = 1
        arquivo      = $leaf
        sha256       = $IntentSha256
        video_id     = $VideoId
        registro_chave = $RecordKey
    }
}
