#requires -Version 7
function Assert-OrdinalStringMap {
    param(
        [Parameter(Mandatory=$false)]
        [object]$Expected,
        [Parameter(Mandatory=$false)]
        [object]$Actual
    )

    if ($null -eq $Expected -or $null -eq $Actual) {
        throw New-Object ArgumentException("Expected e Actual não podem ser nulos.")
    }

    if (-not ($Expected -is [System.Collections.IDictionary]) -or -not ($Actual -is [System.Collections.IDictionary])) {
        throw New-Object ArgumentException("Expected e Actual devem implementar System.Collections.IDictionary.")
    }

    $expectedDict = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    $actualDict   = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)

    foreach ($key in $Expected.Keys) {
        if ($null -eq $key -or $null -eq $Expected[$key]) {
            throw New-Object ArgumentException("Chaves e valores devem ser não nulos.")
        }
        if (-not ($key -is [string]) -or -not ($Expected[$key] -is [string])) {
            throw New-Object ArgumentException("Todas chaves e valores devem ser string.")
        }
        if (-not $expectedDict.TryAdd($key, $Expected[$key])) {
            throw New-Object ArgumentException("Chave duplicada exata encontrada em Expected: '$key'.")
        }
    }

    foreach ($key in $Actual.Keys) {
        if ($null -eq $key -or $null -eq $Actual[$key]) {
            throw New-Object ArgumentException("Chaves e valores devem ser não nulos.")
        }
        if (-not ($key -is [string]) -or -not ($Actual[$key] -is [string])) {
            throw New-Object ArgumentException("Todas chaves e valores devem ser string.")
        }
        if (-not $actualDict.TryAdd($key, $Actual[$key])) {
            throw New-Object ArgumentException("Chave duplicada exata encontrada em Actual: '$key'.")
        }
    }

    if ($expectedDict.Count -ne $actualDict.Count) {
        throw New-Object System.IO.InvalidDataException("Contagem de pares chave-valor diverge: Expected=$($expectedDict.Count), Actual=$($actualDict.Count).")
    }

    foreach ($key in $expectedDict.Keys) {
        if (-not $actualDict.ContainsKey($key)) {
            throw New-Object System.IO.InvalidDataException("Chave '$key' ausente em Actual.")
        }
        if (-not [System.String]::Equals($expectedDict[$key], $actualDict[$key], [System.StringComparison]::Ordinal)) {
            throw New-Object System.IO.InvalidDataException("Valor divergente para chave '$key': Expected='$($expectedDict[$key])', Actual='$($actualDict[$key])'.")
        }
    }

    return $true
}