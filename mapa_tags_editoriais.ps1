#requires -Version 7
function New-EditorialTagMap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)]
        [AllowNull()][object]$Before,
        [Parameter(Mandatory=$false)]
        [AllowNull()][hashtable]$Updates
    )

    # Validar Updates: se $null ou omitido, lançar ArgumentException
    if ($PSBoundParameters.ContainsKey('Updates') -and $null -eq $Updates) {
        throw New-Object ArgumentException("O parâmetro Updates não pode ser $null.")
    }
    if (-not $PSBoundParameters.ContainsKey('Updates')) {
        throw New-Object ArgumentException("O parâmetro Updates é obrigatório.")
    }

    # Validar Before: deve ser $null ou PSCustomObject; rejeitar demais
    if ($null -ne $Before -and $Before -isnot [pscustomobject]) {
        throw New-Object ArgumentException("O parâmetro Before deve ser $null ou um objeto do tipo PSCustomObject.")
    }

    # Criar mapa inicial a partir de Before (se não $null)
    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)

    if ($null -ne $Before) {
        foreach ($prop in $Before.PSObject.Properties) {
            $key = $prop.Name
            $value = $prop.Value

            # Rejeitar se valor não é string
            if ($null -eq $value -or $value -isnot [string]) {
                throw New-Object ArgumentException("A propriedade '$key' de Before deve ser uma string.")
            }

            # Rejeitar se chave duplicada exata
            if (-not $map.TryAdd($key, $value)) {
                throw New-Object ArgumentException("Chave duplicada '$key' encontrada em Before.")
            }
        }
    }

    # Aplicar Updates: validar cada entrada e sobrescrever no mapa
    foreach ($entry in $Updates.GetEnumerator()) {
        $key = $entry.Key
        $value = $entry.Value

        # Validar chave: deve pertencer ao conjunto fixo
        $validKeys = @('artist','title','album','track','composer')
        if ($key -isnot [string] -or [Array]::IndexOf($validKeys, $key) -lt 0) {
            throw New-Object ArgumentException("A chave '$key' não é uma tag editorial válida.")
        }

        # Validar valor: deve ser string, não IsNullOrWhiteSpace e não contém NUL
        if ($null -eq $value -or $value -isnot [string]) {
            throw New-Object ArgumentException("O valor da tag '$key' deve ser uma string.")
        }
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw New-Object ArgumentException("O valor da tag '$key' não pode ser vazio ou apenas espaços.")
        }
        if ($value.Contains([char]0)) {
            throw New-Object ArgumentException("O valor da tag '$key' não pode conter caracteres NUL.")
        }

        # Sobrescrever no mapa (TryAdd não é usado aqui pois Updates substituem)
        $map[$key] = $value
    }

    # Retornar copia independente; Dictionary permanece mutavel
    return ,$map
}
