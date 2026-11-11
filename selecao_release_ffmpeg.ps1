#requires -Version 7.0
# Somente cabecalhos: nao valida assets ou o restante do corpo da API.
function Select-FfmpegDatedRelease {
    param([AllowNull()][object]$Json)
    if($Json -isnot [string] -or [string]::IsNullOrWhiteSpace($Json) -or $Json.Length -gt 2097152){throw [ArgumentException]::new('Json deve ser string nao vazia de ate 2097152 caracteres')}
    $options=[System.Text.Json.JsonDocumentOptions]::new();$options.MaxDepth=16
    $document=$null
    try {
        $document=[System.Text.Json.JsonDocument]::Parse([string]$Json,$options)
        $root=$document.RootElement
        if($root.ValueKind -ne [System.Text.Json.JsonValueKind]::Array -or $root.GetArrayLength() -lt 1 -or $root.GetArrayLength() -gt 20){throw [ArgumentException]::new('Raiz deve ser array com 1 a 20 objetos')}
        $selected=$null
        $tags=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $required=@('tag_name','draft','prerelease')
        foreach($record in $root.EnumerateArray()) {
            if($record.ValueKind -ne [System.Text.Json.JsonValueKind]::Object){throw [ArgumentException]::new('Registro deve ser objeto')}
            $fields=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
            foreach($property in $record.EnumerateObject()) {
                if($property.Name -cin $required){
                    if(!$fields.TryAdd($property.Name,$property.Value)){throw [ArgumentException]::new('Campo requerido duplicado')}
                }elseif($property.Name.ToLowerInvariant() -cin $required){throw [ArgumentException]::new('Alias de caixa em campo requerido')}
            }
            if($fields.Count -ne 3){throw [ArgumentException]::new('Campo requerido ausente')}
            if($fields['tag_name'].ValueKind -ne [System.Text.Json.JsonValueKind]::String){throw [ArgumentException]::new('tag_name deve ser string')}
            $tag=$fields['tag_name'].GetString()
            if([string]::IsNullOrWhiteSpace($tag) -or $tag.Length -gt 128){throw [ArgumentException]::new('tag_name vazia ou longa')}
            foreach($flag in @('draft','prerelease')) {
                if($fields[$flag].ValueKind -notin @([System.Text.Json.JsonValueKind]::True,[System.Text.Json.JsonValueKind]::False)){throw [ArgumentException]::new('Flag deve ser booleana')}
            }
            if($fields['draft'].GetBoolean() -or $fields['prerelease'].GetBoolean()){continue}
            if($tag -cnotmatch '\Aautobuild-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}\z'){continue}
            $date=[DateTime]::MinValue
            if(![DateTime]::TryParseExact($tag.Substring('autobuild-'.Length),'yyyy-MM-dd-HH-mm',[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$date)){throw [ArgumentException]::new('Calendario da tag invalido')}
            if(!$tags.Add($tag)){throw [ArgumentException]::new('Tag candidata duplicada')}
            if($null -eq $selected -or [StringComparer]::Ordinal.Compare($tag,$selected) -gt 0){$selected=$tag}
        }
        if($null -eq $selected){throw [ArgumentException]::new('Nenhuma release datada elegivel')}
        return $selected
    }
    finally {if($null -ne $document){$document.Dispose()}}
}
