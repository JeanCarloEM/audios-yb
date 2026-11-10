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

function Resolve-AutoSearchAudioSelectionProof([object]$VideoId = $null, [object]$SourceUrl = $null, [object]$Artist = $null, [object]$Song = $null, [object]$StoredProof = $null) {
    $validateStoredProof = {
        param([object]$obj)
        if ($obj -isnot [System.Collections.IDictionary]) { return $false }
        if ($obj.Count -ne 7) { return $false }
        $requiredKeys = @('versao', 'tipo', 'video_id', 'criterio', 'metadados', 'referencia', 'candidatos')
        $keySet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($k in $obj.Keys) {
            if ($k -isnot [string]) { return $false }
            if (-not $requiredKeys.Contains($k)) { return $false }
            [void]$keySet.Add($k)
        }
        if ($keySet.Count -ne 7) { return $false }
        foreach ($k in $requiredKeys) {
            if (-not $keySet.Contains($k)) { return $false }
        }
        if ($obj['versao'] -isnot [int] -and $obj['versao'] -isnot [long]) { return $false }
        if ($obj['versao'] -ne 3) { return $false }
        if ($obj['tipo'] -isnot [string] -or $obj['tipo'] -cne 'selecao_tecnica') { return $false }
        if ($obj['criterio'] -isnot [string] -or $obj['criterio'] -cne 'busca_exata_canal_artista_unica') { return $false }
        if ($obj['video_id'] -isnot [string]) { return $false }
        $metadados = $obj['metadados']
        if ($metadados -isnot [System.Collections.IDictionary]) { return $false }
        if ($metadados.Count -ne 3) { return $false }
        $metaKeys = @('id', 'title', 'channel')
        $metaHashSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($k in $metadados.Keys) {
            if ($k -isnot [string]) { return $false }
            if (-not $metaKeys.Contains($k)) { return $false }
            [void]$metaHashSet.Add($k)
        }
        if ($metaHashSet.Count -ne 3) { return $false }
        foreach ($k in $metaKeys) {
            if (-not $metaHashSet.Contains($k)) { return $false }
        }
        if ($metadados['id'] -isnot [string] -or $metadados['id'].Length -ne 11 -or $metadados['id'] -match '[^A-Za-z0-9_-]') { return $false }
        if ($metadados['title'] -isnot [string] -or $metadados['title'].Trim() -eq '') { return $false }
        if ($metadados['channel'] -isnot [string] -or $metadados['channel'].Trim() -eq '') { return $false }
        $referencia = $obj['referencia']
        if ($referencia -isnot [System.Collections.IDictionary]) { return $false }
        if ($referencia.Count -ne 4) { return $false }
        $refKeys = @('artista', 'musica', 'url_original', 'consulta')
        $refHashSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($k in $referencia.Keys) {
            if ($k -isnot [string]) { return $false }
            if (-not $refKeys.Contains($k)) { return $false }
            [void]$refHashSet.Add($k)
        }
        if ($refHashSet.Count -ne 4) { return $false }
        foreach ($k in $refKeys) {
            if (-not $refHashSet.Contains($k)) { return $false }
        }
        if ($referencia['artista'] -isnot [string]) { return $false }
        if ($referencia['musica'] -isnot [string]) { return $false }
        if ($referencia['url_original'] -isnot [string]) { return $false }
        if ($referencia['consulta'] -isnot [string]) { return $false }
        $candidatos = $obj['candidatos']
        if ($candidatos -isnot [System.Collections.IList]) { return $false }
        if ($candidatos.Count -eq 0) { return $false }
        foreach ($c in $candidatos) {
            if ($c -isnot [System.Collections.IDictionary]) { return $false }
            if ($c.Count -ne 3) { return $false }
            $candKeys = @('id', 'titulo', 'canal')
            $candHashSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
            foreach ($k in $c.Keys) {
                if ($k -isnot [string]) { return $false }
                if (-not $candKeys.Contains($k)) { return $false }
                [void]$candHashSet.Add($k)
            }
            if ($candHashSet.Count -ne 3) { return $false }
            foreach ($k in $candKeys) {
                if (-not $candHashSet.Contains($k)) { return $false }
            }
            if ($c['id'] -isnot [string] -or $c['id'].Length -ne 11 -or $c['id'] -match '[^A-Za-z0-9_-]') { return $false }
            if ($c['titulo'] -isnot [string] -or $c['titulo'].Trim() -eq '') { return $false }
            if ($c['canal'] -isnot [string] -or $c['canal'].Trim() -eq '') { return $false }
        }
        return $true
    }

    if (-not (& $validateStoredProof $StoredProof)) { return $null }

    $storedVideoId = $StoredProof['video_id']
    $storedArtist = $StoredProof['referencia']['artista']
    $storedSong = $StoredProof['referencia']['musica']
    $storedSourceUrl = $StoredProof['referencia']['url_original']
    $storedQuery = $StoredProof['referencia']['consulta']
    # Contexto esperado e prova devem coincidir literalmente.
    foreach ($pair in @(@($VideoId,$storedVideoId),@($Artist,$storedArtist),@($Song,$storedSong),@($SourceUrl,$storedSourceUrl))) {
        if ($pair[0] -isnot [string] -or -not [string]::Equals($pair[0],$pair[1],[StringComparison]::Ordinal)) { return $null }
    }
    $storedCandidates = @()
    foreach ($c in $StoredProof['candidatos']) {
        $storedCandidates += @{id = $c['id']; titulo = $c['titulo']; canal = $c['canal']}
    }
    $storedInfo = @{
        id = $StoredProof['metadados']['id']
        title = $StoredProof['metadados']['title']
        channel = $StoredProof['metadados']['channel']
    }

    try {
        $query = Get-CanonicalAudioSearchQuery -SourceUrl $SourceUrl
        if (-not [string]::Equals($storedQuery,$query,[StringComparison]::Ordinal)) { return $null }
        return New-AutoSearchAudioSelectionProof -VideoId $VideoId -SourceUrl $SourceUrl -Artist $Artist -Song $Song -Candidates $storedCandidates -Info $storedInfo
    } catch [ArgumentException] {
        return $null
    }
}
