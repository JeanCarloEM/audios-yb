#requires -Version 7.0
function New-AutoSearchAudioSelectionProof([object]$VideoId = $null, [object]$SourceUrl = $null, [object]$Artist = $null, [object]$Song = $null, [object]$Candidates = $null, [object]$Info = $null) {
    if ($VideoId -isnot [string] -or $VideoId.Length -ne 11 -or $VideoId -match '[^A-Za-z0-9_-]') {
        throw [ArgumentException]::new('VideoId deve ser string ASCII de 11 caracteres')
    }
    $query = Get-CanonicalAudioSearchQuery -SourceUrl $SourceUrl
    if ($Artist -isnot [string] -or $Artist.Trim() -eq '') {
        throw [ArgumentException]::new('Artist deve ser string nao vazia')
    }
    if ($Song -isnot [string] -or $Song.Trim() -eq '') {
        throw [ArgumentException]::new('Song deve ser string nao vazia')
    }
    $queryFrame = ' ' + (Normal $query) + ' '
    foreach ($label in @($Artist, $Song)) {
        $normalizedLabel = Normal $label
        if ($normalizedLabel.Length -eq 0 -or -not $queryFrame.Contains((' ' + $normalizedLabel + ' '), [StringComparison]::Ordinal)) {
            throw [ArgumentException]::new('Consulta nao corresponde aos dados canonicos')
        }
    }
    if ($null -eq $Candidates -or $Candidates -isnot [System.Collections.IList] -or $Candidates.Count -eq 0) {
        throw [ArgumentException]::new('Candidates deve ser lista nao vazia')
    }
    $candidatesCopy = @()
    foreach ($item in $Candidates) {
        if ($item -isnot [System.Collections.IDictionary]) {
            throw [ArgumentException]::new('Cada entrada de Candidates deve ser IDictionary')
        }
        foreach ($requiredKey in @('id','titulo','canal')) {
            $found = $false
            foreach ($key in $item.Keys) {
                if ($key -is [string] -and [string]::Equals($key, $requiredKey, [StringComparison]::OrdinalIgnoreCase)) {
                    if (-not [string]::Equals($key, $requiredKey, [StringComparison]::Ordinal)) { throw [ArgumentException]::new('Nome de campo nao canonico') }
                    $found = $true
                }
            }
            if (-not $found) { throw [ArgumentException]::new('Campo canonico ausente') }
        }
        $idVal = $item['id']
        $titVal = $item['titulo']
        $canVal = $item['canal']
        if ($idVal -isnot [string] -or $idVal.Length -ne 11 -or $idVal -match '[^A-Za-z0-9_-]') {
            throw [ArgumentException]::new('id de Candidates deve ser string ASCII 11 caracteres')
        }
        if ($titVal -isnot [string] -or $titVal.Trim() -eq '') {
            throw [ArgumentException]::new('titulo de Candidates deve ser string nao vazia')
        }
        if ($canVal -isnot [string] -or $canVal.Trim() -eq '') {
            throw [ArgumentException]::new('canal de Candidates deve ser string nao vazia')
        }
        $candidatesCopy += @{id = $idVal; titulo = $titVal; canal = $canVal}
    }
    if ($Info -eq $null -or $Info -isnot [System.Collections.IDictionary]) {
        throw [ArgumentException]::new('Info deve ser IDictionary')
    }
    foreach ($requiredKey in @('id','title','channel')) {
        $found = $false
        foreach ($key in $Info.Keys) {
            if ($key -is [string] -and [string]::Equals($key, $requiredKey, [StringComparison]::OrdinalIgnoreCase)) {
                if (-not [string]::Equals($key, $requiredKey, [StringComparison]::Ordinal)) { throw [ArgumentException]::new('Nome de campo nao canonico') }
                $found = $true
            }
        }
        if (-not $found) { throw [ArgumentException]::new('Campo canonico ausente') }
    }
    $infoId = $Info['id']
    $infoTitle = $Info['title']
    $infoChannel = $Info['channel']
    if ($infoId -isnot [string] -or $infoId.Length -ne 11 -or $infoId -match '[^A-Za-z0-9_-]') {
        throw [ArgumentException]::new('id de Info deve ser string ASCII 11 caracteres')
    }
    if ($infoTitle -isnot [string] -or $infoTitle.Trim() -eq '') {
        throw [ArgumentException]::new('title de Info deve ser string nao vazia')
    }
    if ($infoChannel -isnot [string] -or $infoChannel.Trim() -eq '') {
        throw [ArgumentException]::new('channel de Info deve ser string nao vazia')
    }
    if (-not [string]::Equals($infoId, $VideoId, [StringComparison]::Ordinal)) {
        throw [ArgumentException]::new('Info.id deve ser igual a VideoId')
    }
    if (-not (Is-ExactArtistAudio $infoTitle $infoChannel $Artist $Song)) {
        throw [ArgumentException]::new('Info.title/channel devem corresponder a IsExactArtistAudio')
    }
    $selected = Select-AutoCandidate $candidatesCopy $Artist $Song
    if ($null -eq $selected) {
        throw [ArgumentException]::new('Nenhum candidato corresponde a IsExactArtistAudio')
    }
    if (-not [string]::Equals([string]$selected.id, $VideoId, [StringComparison]::Ordinal)) {
        throw [ArgumentException]::new('Candidato selecionado diverge do ID literal')
    }
    $metadados = @{id = $infoId; title = $infoTitle; channel = $infoChannel}
    $referencia = @{artista = $Artist; musica = $Song; url_original = $SourceUrl; consulta = $query}
    $candidatosOutput = $candidatesCopy
    return @{
        versao = [int]3
        tipo = 'selecao_tecnica'
        video_id = $VideoId
        criterio = 'busca_exata_canal_artista_unica'
        metadados = $metadados
        referencia = $referencia
        candidatos = $candidatosOutput
    }
}
