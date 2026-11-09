function Resolve-VocalPreference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$Global = 'indiferentes',

        [Parameter(Mandatory = $false)]
        [string]$Individual = $null
    )

    $normalizedIndividual = $null
    if ($null -ne $Individual -and $Individual.Trim() -ne '') {
        $normalizedIndividual = $Individual.Trim().ToLowerInvariant()
    }

    $normalizedGlobal = if ([string]::IsNullOrWhiteSpace($Global)) { 'indiferentes' } else { $Global.Trim().ToLowerInvariant() }

    $validValues = [System.Collections.Generic.HashSet[string]]::new([string[]]@('vocais', 'instrumentais', 'indiferentes'), [StringComparer]::Ordinal)

    if ($null -ne $normalizedIndividual -and -not $validValues.Contains($normalizedIndividual)) {
    throw [ArgumentException]::new("Valor efetivo inválido para preferência vocal.")
    }

    if ($null -ne $normalizedIndividual -and $validValues.Contains($normalizedIndividual)) {
        return $normalizedIndividual
    }

    if ($validValues.Contains($normalizedGlobal)) {
        return $normalizedGlobal
    }

    throw [ArgumentException]::new("Valor efetivo inválido para preferência vocal.")
}
