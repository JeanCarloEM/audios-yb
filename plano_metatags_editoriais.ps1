#requires -Version 7
# Rotulos de origem nao autenticam dados; conflito/unsupported bloqueia toda a operacao.
function Get-EditorialTagPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$CurrentValues,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$RequestedValues,

        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object]$RequestedSources
    )

    # Validação de tipos e conversão para Dictionary[string,object] Ordinal
    if($null -eq $RequestedValues){throw [ArgumentException]::new('RequestedValues obrigatorio')}
    $maps=@()
    foreach($table in @($CurrentValues,$RequestedValues,$RequestedSources)){
        if($null -ne $table -and $table -isnot [System.Collections.IDictionary]){throw [ArgumentException]::new('Mapa invalido')}
        $copy=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
        if($null -ne $table){
            foreach($key in $table.Keys){
                if($key -isnot [string]){throw [ArgumentException]::new('Chave deve ser string')}
                if(-not $copy.TryAdd($key,$table[$key])){throw [ArgumentException]::new('Chave duplicada')}
            }
        }
        $maps+=,$copy
    }
    $currentDict=$maps[0];$requestedDict=$maps[1];$sourcesDict=$maps[2]

    # Validação de chaves RequestedValues e RequestedSources: somente 5 allowlist lower exatos
    $allowedKeys = @("artist", "title", "album", "track", "composer")
    foreach ($k in $requestedDict.Keys) {
        if ([Array]::IndexOf($allowedKeys, $k) -lt 0) {
            throw [System.ArgumentException]::new("RequestedValues contém chave não permitida: $k")
        }
    }
    foreach ($k in $sourcesDict.Keys) {
        if ([Array]::IndexOf($allowedKeys, $k) -lt 0) {
            throw [System.ArgumentException]::new("RequestedSources contém chave não permitida: $k")
        }
    }

    # Validação de valores RequestedSources: null ou string
    foreach ($k in $sourcesDict.Keys) {
        $v = $sourcesDict[$k]
        if ($null -ne $v -and $v -isnot [string]) {
            throw [System.ArgumentException]::new("RequestedSources[$k] deve ser null ou string.")
        }
    }

    # Validação de valores RequestedValues: string não contendo NUL
    foreach ($k in $requestedDict.Keys) {
        $v = $requestedDict[$k]
        if ($v -is [string] -and $v.Contains("`0")) {
            throw [System.ArgumentException]::new("RequestedValues[$k] contém caractere NUL.")
        }
    }

    # Loop fixo 5 tags: artist/title/album/track/composer
    $tagOrder = @("artist", "title", "album", "track", "composer")
    $decisions = @()
    $updates = [ordered]@{}
    $hasConflictOrUnsupported = $false

    foreach ($tag in $tagOrder) {
        $currentRaw = $null
        $requestedRaw = $null
        $sourceRaw = $null

        if ($currentDict.ContainsKey($tag)) {
            $currentRaw = $currentDict[$tag]
        }
        if ($requestedDict.ContainsKey($tag)) {
            $requestedRaw = $requestedDict[$tag]
        }
        if ($sourcesDict.ContainsKey($tag)) {
            $sourceRaw = $sourcesDict[$tag]
        }

        $decision = Get-EditorialTagValueDecision -CurrentValue $currentRaw -RequestedValue $requestedRaw -RequestedSource $sourceRaw

        $decisionObj = [PSCustomObject]@{
            Tag = $tag
            Decision = $decision
        }
        $decisions += $decisionObj

        if ($decision.Action -eq "apply") {
            $updates[$tag] = $decision.Value
        }

        if ($decision.Action -eq "conflict" -or $decision.Action -eq "unsupported") {
            $hasConflictOrUnsupported = $true
        }
    }

    $resultUpdates = @{}
    if ($hasConflictOrUnsupported) {
        $resultReady = $false
        $resultUpdates = @{}
    } else {
        $resultReady = $true
        foreach ($k in $updates.Keys) {
            $resultUpdates[$k] = $updates[$k]
        }
    }

    [PSCustomObject]@{
        Ready = $resultReady
        Updates = $resultUpdates
        Decisions = $decisions
    }
}