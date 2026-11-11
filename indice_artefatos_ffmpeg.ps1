#requires -Version 7.0
. (Join-Path $PSScriptRoot 'selecao_release_ffmpeg.ps1')
function Read-FfmpegAssetIndex {
    param([AllowNull()][object]$Json)
    if ($Json -isnot [string] -or [string]::IsNullOrWhiteSpace($Json) -or $Json.Length -gt 2097152) {
        throw [ArgumentException]::new('Json deve ser string nao vazia de ate 2097152 caracteres')
    }
    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.MaxDepth = 16
    $document = $null
    try {
        $document = [System.Text.Json.JsonDocument]::Parse([string]$Json, $options)
        $root = $document.RootElement
        if ($root.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
            throw [ArgumentException]::new('Raiz deve ser objeto')
        }
        $fields = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        $requiredRoot = @('tag_name', 'draft', 'prerelease', 'assets')
        $assetsFound = $false
        foreach ($property in $root.EnumerateObject()) {
            if ($property.Name -cin $requiredRoot) {
                if (!$fields.TryAdd($property.Name, $property.Value)) {
                    throw [ArgumentException]::new('Campo requerido duplicado')
                }
            } elseif ($property.Name.ToLowerInvariant() -cin $requiredRoot) {
                throw [ArgumentException]::new('Alias de caixa em campo requerido')
            } elseif ($property.Name -ceq 'assets') {
                if ($assetsFound) {
                    throw [ArgumentException]::new('assets duplicado')
                }
                $assetsFound = $true
                $fields.Add('assets', $property.Value)
            }
        }
        if ($fields.Count -ne 4) {
            throw [ArgumentException]::new('Campos requeridos ausentes')
        }
        if ($fields['tag_name'].ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
            throw [ArgumentException]::new('tag_name deve ser string')
        }
        $tag = $fields['tag_name'].GetString()
        if ([string]::IsNullOrWhiteSpace($tag) -or $tag.Length -gt 128) {
            throw [ArgumentException]::new('tag_name vazia ou longa')
        }
        foreach ($flag in @('draft', 'prerelease')) {
            if ($fields[$flag].ValueKind -notin @([System.Text.Json.JsonValueKind]::True, [System.Text.Json.JsonValueKind]::False)) {
                throw [ArgumentException]::new('Flag deve ser booleana')
            }
        }
        if ($fields['draft'].GetBoolean() -or $fields['prerelease'].GetBoolean()) {
            throw [ArgumentException]::new('Draft ou prerelease nao permitidos')
        }
        $header = '[{"tag_name":' + $fields['tag_name'].GetRawText() + ',"draft":' + $fields['draft'].GetRawText() + ',"prerelease":' + $fields['prerelease'].GetRawText() + '}]'
        $tag = Select-FfmpegDatedRelease -Json $header
        $assetsElement = $fields['assets']
        if ($assetsElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Array) {
            throw [ArgumentException]::new('assets deve ser array')
        }
        $assetCount = $assetsElement.GetArrayLength()
        if ($assetCount -lt 1 -or $assetCount -gt 256) {
            throw [ArgumentException]::new('assets deve ter entre 1 e 256 elementos')
        }
        $assetList = New-Object System.Collections.Generic.List[hashtable]
        $nameSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::Ordinal)
        foreach ($assetObj in $assetsElement.EnumerateArray()) {
            if ($assetObj.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
                throw [ArgumentException]::new('Asset deve ser objeto')
            }
            $assetFields = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
            $nameFound = $false
            $sizeFound = $false
            $digestFound = $false
            foreach ($prop in $assetObj.EnumerateObject()) {
                $pName = $prop.Name
                if ($pName -cnotin @('name', 'size', 'digest') -and $pName.ToLowerInvariant() -cin @('name', 'size', 'digest')) { throw [ArgumentException]::new('Alias de caixa em campo de asset') }
                if ($pName -ceq 'name') {
                    if ($nameFound) { throw [ArgumentException]::new('name duplicado') }
                    if ($prop.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
                        throw [ArgumentException]::new('name deve ser string')
                    }
                    $nVal = $prop.Value.GetString()
                    if ([string]::IsNullOrWhiteSpace($nVal) -or $nVal.Length -gt 255) {
                        throw [ArgumentException]::new('name vazio, whitespace ou longo')
                    }
                    if (!$nameSet.Add($nVal)) { throw [ArgumentException]::new('name duplicado') }
                    $assetFields.Add('name', $nVal)
                    $nameFound = $true
                } elseif ($pName -ceq 'Size') {
                    throw [ArgumentException]::new('Alias de caixa em size')
                } elseif ($pName -ceq 'size') {
                    if ($sizeFound) { throw [ArgumentException]::new('size duplicado') }
                    if ($prop.Value.ValueKind -ne [System.Text.Json.JsonValueKind]::Number) {
                        throw [ArgumentException]::new('size deve ser numero')
                    }
                    $sVal = [long]0
                    if (!$prop.Value.TryGetInt64([ref]$sVal)) {
                        throw [ArgumentException]::new('size fora de alcance Int64')
                    }
                    if ($sVal -lt 0) {
                        throw [ArgumentException]::new('size negativo')
                    }
                    $assetFields.Add('size', $sVal)
                    $sizeFound = $true
                } elseif ($pName -ceq 'digest') {
                    if ($digestFound) { throw [ArgumentException]::new('digest duplicado') }
                    if ($prop.Value.ValueKind -eq [System.Text.Json.JsonValueKind]::Null) {
                        $assetFields.Add('digest', $null)
                    } elseif ($prop.Value.ValueKind -eq [System.Text.Json.JsonValueKind]::String) {
                        $dVal = $prop.Value.GetString()
                        if ($dVal -cmatch '^sha256:') {
                            $hexPart = $dVal.Substring(7)
                            if ($hexPart.Length -ne 64 -or $hexPart -cnotmatch '^[A-Fa-f0-9]{64}$') {
                                throw [ArgumentException]::new('digest sha256 invalido')
                            }
                            $assetFields.Add('digest', $hexPart.ToLowerInvariant())
                        } else {
                            throw [ArgumentException]::new('digest sem prefixo sha256')
                        }
                    } else {
                        throw [ArgumentException]::new('digest deve ser string ou null')
                    }
                    $digestFound = $true
                } elseif ($pName -ceq 'Name' -or $pName -ceq 'NAME') {
                    throw [ArgumentException]::new('Alias de caixa em name')
                } elseif ($pName -ceq 'Size' -or $pName -ceq 'SIZE') {
                    throw [ArgumentException]::new('Alias de caixa em size')
                } elseif ($pName -ceq 'Digest' -or $pName -ceq 'DIGEST') {
                    throw [ArgumentException]::new('Alias de caixa em digest')
                }
            }
            if (!$nameFound -or !$sizeFound) {
                throw [ArgumentException]::new('name ou size ausente')
            }
            $assetMap = @{
                name   = $assetFields['name']
                size   = $assetFields['size']
                sha256 = if ($assetFields.ContainsKey('digest')) { $assetFields['digest'] } else { $null }
            }
            $assetList.Add($assetMap)
        }
        $releaseTag = $tag
        $assetsArray = $assetList.ToArray()
        return @{
            release_tag = $releaseTag
            assets      = $assetsArray
        }
    }
    finally {
        if ($null -ne $document) { $document.Dispose() }
    }
}
