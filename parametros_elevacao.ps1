#requires -Version 7.0
function ConvertTo-ElevationParameterPayload {
    [CmdletBinding()]
    param(
        [AllowNull()][object]$BoundParameters
    )
    if ($null -eq $BoundParameters) { throw "BoundParameters não pode ser nulo." }
    if ($BoundParameters -isnot [System.Collections.IDictionary]) { throw "BoundParameters deve ser um IDictionary." }
    if ($BoundParameters.Count -gt 64) { throw "Número de entradas excede 64." }
    $keySet = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $result = @{}
    foreach ($entry in $BoundParameters.GetEnumerator()) {
        $key = $entry.Key
        $value = $entry.Value
        if ($key -isnot [string]) { throw "Chave deve ser string." }
        if ($key.Length -eq 0 -or $key.Length -gt 128) { throw "Chave deve ter entre 1 e 128 caracteres." }
        if ($key -cnotmatch '\A[A-Za-z][A-Za-z0-9_]*\z') { throw "Chave inválida." }
        if (-not $keySet.Add($key)) { throw "Chave duplicada (OrdinalIgnoreCase)." }
        if ($null -ne $value) {
            $t = $value.GetType()
            if ($t -notin @([string], [int], [bool], [Management.Automation.SwitchParameter], [Management.Automation.ActionPreference])) { throw "Tipo de valor inválido." }
        }
        $result[$key] = $value
    }
    $envelope = @{
        version = 1
        parameters = $result
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes([Management.Automation.PSSerializer]::Serialize($envelope, 4))
    if ($bytes.Length -gt 1048576) { throw "Payload serializado excede 1 MiB." }
    return [Convert]::ToBase64String($bytes)
}
