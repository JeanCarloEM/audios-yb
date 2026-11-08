function Get-CsvMusicalNameComponents {
    param(
        [Parameter(Mandatory=$false)]
        [AllowNull()]
        [object]$Row,
        [string]$ColunaAutor,
        [string]$ColunaTrack,
        [string]$ColunaTitulo,
        [nullable[int]]$LarguraTrack = $null
    )

    # Fallback se Row for $null
    if ($null -eq $Row) {
        return @{
            usar_legado = $true
            componentes = [string[]]@()
            motivo = "Row é nulo"
        }
    }

    # Função auxiliar para verificar se valor é string/null/whitespace
    function Test-ValidStringValue {
        param([object]$value)
        if ($null -eq $value) { return $true }
        if ($value -isnot [string]) { return $false }
        return $true
    }

    # Função auxiliar para normalizar valor de título (null/whitespace => fallback)
    function Normalize-TitleValue {
        param([object]$value)
        if ($null -eq $value) { return $null }
        if ($value -isnot [string]) { return $null }
        if ([string]::IsNullOrWhiteSpace($value)) { return $null }
        return $value
    }

    # Verifica colunas solicitadas e valores
    $valorAutor = $null
    $valorTrack = $null
    $valorTitulo = $null

    # Busca de propriedade literal via foreach e [string]::Equals
    $propAutor = $null
    $propTrack = $null
    $propTitulo = $null

    foreach ($prop in $Row.PSObject.Properties) {
        if ([string]::Equals($prop.Name, $ColunaAutor, [StringComparison]::Ordinal)) {
            $propAutor = $prop
        }
        if ([string]::Equals($prop.Name, $ColunaTrack, [StringComparison]::Ordinal)) {
            $propTrack = $prop
        }
        if ([string]::Equals($prop.Name, $ColunaTitulo, [StringComparison]::Ordinal)) {
            $propTitulo = $prop
        }
    }

    $fallback = @{ usar_legado = $true; componentes = [string[]]@(); motivo = 'Mapeamento ausente ou invalido' }
if ([string]::IsNullOrWhiteSpace($ColunaTitulo) -or $propTitulo -eq $null) { return $fallback }; $celulaTitulo = $propTitulo.Value; if ($null -ne $celulaTitulo -and $celulaTitulo -isnot [string]) { return $fallback }; $valorTitulo = $celulaTitulo; if ([string]::IsNullOrWhiteSpace($ColunaAutor)) { $valorAutor = $null } else { if ($null -eq $propAutor) { return $fallback }; $celulaAutor = $propAutor.Value; if ($null -ne $celulaAutor -and $celulaAutor -isnot [string]) { return $fallback }; $valorAutor = $celulaAutor }; if ([string]::IsNullOrWhiteSpace($ColunaTrack)) { $valorTrack = $null } else { if ($null -eq $propTrack) { return $fallback }; $celulaTrack = $propTrack.Value; if ($null -ne $celulaTrack -and $celulaTrack -isnot [string]) { return $fallback }; $valorTrack = $celulaTrack }
    # Chama API existente com valores mapeados
    $componentes = Get-MusicalNameComponents -Autor $valorAutor -Track $valorTrack -Titulo $valorTitulo -LarguraTrack $LarguraTrack

    return $componentes
}