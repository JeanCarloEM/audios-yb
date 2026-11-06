#requires -Version 7.0
# RCF 7.3: normalizacao pura; ainda sem integracao ao principal/tags.
function ConvertTo-CollectionMarker {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [AllowNull()][AllowEmptyString()][string]$Value = ''
    )
    if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
    $normalized = $Value.Trim().Normalize([Text.NormalizationForm]::FormC)
    $letters = @(
        [Globalization.UnicodeCategory]::UppercaseLetter,
        [Globalization.UnicodeCategory]::LowercaseLetter,
        [Globalization.UnicodeCategory]::TitlecaseLetter,
        [Globalization.UnicodeCategory]::ModifierLetter,
        [Globalization.UnicodeCategory]::OtherLetter
    )
    $result = [Text.StringBuilder]::new()
    $firstLetter = $true
    for ($offset = 0; $offset -lt $normalized.Length;) {
        $width = 1
        if ([char]::IsHighSurrogate($normalized[$offset]) -and
            $offset + 1 -lt $normalized.Length -and
            [char]::IsLowSurrogate($normalized[$offset + 1])) { $width = 2 }
        $part = $normalized.Substring($offset, $width)
        $category = [Globalization.CharUnicodeInfo]::GetUnicodeCategory($normalized, $offset)
        if ($category -in $letters) {
            if ($firstLetter) { $part = $part.ToUpperInvariant(); $firstLetter = $false }
            else { $part = $part.ToLowerInvariant() }
        }
        [void]$result.Append($part)
        $offset += $width
    }
    return $result.ToString().Normalize([Text.NormalizationForm]::FormC)
}

# RCF 7.3: decisao deterministica sem I/O, subprocessos ou midia.
function Get-CollectionMarkerDecision {
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyString()][string]$CurrentValue = '',
        [AllowNull()][AllowEmptyString()][string]$RequestedValue = ''
    )
    $normalizedRequested = ConvertTo-CollectionMarker -Value $RequestedValue
    if ([string]::IsNullOrEmpty($normalizedRequested)) {
        return [PSCustomObject]@{ Action = 'keep'; Value = $CurrentValue; Reason = 'absent' }
    }
    if ([string]::IsNullOrEmpty($CurrentValue)) {
        return [PSCustomObject]@{ Action = 'apply'; Value = $normalizedRequested; Reason = 'empty_field' }
    }
    if ([string]::Equals($normalizedRequested, $CurrentValue, [StringComparison]::Ordinal)) {
        return [PSCustomObject]@{ Action = 'keep'; Value = $CurrentValue; Reason = 'already_present' }
    }
    return [PSCustomObject]@{ Action = 'unsupported'; Value = $CurrentValue; Reason = 'multiple_values_not_validated' }
}

# RCF 7.3: hash comprimido de áudio via ffmpeg hash mode
function Get-CompressedAudioHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$File,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Ffmpeg
    )

    if (-not (Test-Path -LiteralPath $File -PathType Leaf)) {
        throw [System.IO.FileNotFoundException]::new("Arquivo não encontrado: $File", $File)
    }

    $result = Invoke-Ytdlp -Executable $Ffmpeg -Arguments @('-v', 'error', '-i', $File, '-map', '0:a:0', '-c:a', 'copy', '-f', 'hash', '-hash', 'sha256', '-') -TimeoutSeconds 30

    if ($result.timeout -eq $true) {
        throw [System.TimeoutException]::new("Timeout ao processar: $File")
    }

    if ($result.code -ne 0) {
        throw [System.InvalidOperationException]::new("Comando falhou: $($result.err)")
    }

    $match = [regex]::Match($result.out, '(?im)^SHA256=([0-9a-f]{64})\s*$')
    if (-not $match.Success) {
        throw [System.InvalidOperationException]::new("Hash não encontrado na saída: $($result.out)")
    }

    return $match.Groups[1].Value.ToUpperInvariant()
}


function Get-AudioMetadataSnapshot {
 [CmdletBinding()]
 param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$File,
       [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Ffprobe)
 if(-not (Test-Path -LiteralPath $File -PathType Leaf)){throw [IO.FileNotFoundException]::new('Arquivo ausente',$File)}
 $run=Invoke-Ytdlp -Executable $Ffprobe -Arguments @('-v','error','-protocol_whitelist','file','-show_streams','-show_format','-of','json','-i',$File) -TimeoutSeconds 30
 if($run.timeout){throw [TimeoutException]::new('Timeout ao ler metadados')}
 if($run.code -ne 0){throw [InvalidOperationException]::new('ffprobe: '+$run.err)}
 $info=ConvertFrom-Json -InputObject $run.out -ErrorAction Stop
 if($null -eq $info.format -or @($info.streams).Count -ne 1 -or $info.streams[0].codec_type -cne 'audio'){throw [IO.InvalidDataException]::new('Exigir formato e exatamente um stream de audio')}
 return $info
}

# Candidato ainda nao validado: validar qualidade, tags e payload antes de publicar.
function New-Mp3MarkerCandidate {
 [CmdletBinding()]
 param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$File,
       [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Output,
       [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$Marker,
       [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Ffmpeg)
 if(-not (Test-Path -LiteralPath $File -PathType Leaf)){throw [IO.FileNotFoundException]::new('Arquivo ausente',$File)}
 $sourcePath=[IO.Path]::GetFullPath($File); $candidatePath=[IO.Path]::GetFullPath($Output)
 $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
 if([string]::Equals($sourcePath,$candidatePath,$comparison)){throw [ArgumentException]::new('Candidato deve diferir da fonte')}
 if(Test-Path -LiteralPath $candidatePath){throw [IO.IOException]::new('Destino ja existe')}
 $normalized=ConvertTo-CollectionMarker -Value $Marker
 if([string]::IsNullOrEmpty($normalized)){throw [ArgumentException]::new('Marcador vazio')}
 $run=Invoke-Ytdlp -Executable $Ffmpeg -Arguments @('-nostdin','-v','error','-protocol_whitelist','file','-i',$sourcePath,'-map','0:a:0','-map_metadata','0','-c:a','copy','-id3v2_version','3','-metadata',('marcador_coletanea='+$normalized),'-n',$candidatePath) -TimeoutSeconds 180
 if($run.timeout){throw [TimeoutException]::new('Timeout ao criar candidato')}
 if($run.code -ne 0){throw [InvalidOperationException]::new('ffmpeg: '+$run.err)}
 if(-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)){throw [IO.InvalidDataException]::new('Candidato ausente')}
 if((Get-Item -LiteralPath $candidatePath).Length -le 0){throw [IO.InvalidDataException]::new('Candidato vazio')}
 return [pscustomobject]@{SourcePath=$sourcePath;CandidatePath=$candidatePath;Marker=$normalized;Validated=$false}
}

# Verifica somente preservacao de tags; nao valida marcador, audio ou publicacao.
function Assert-MarkerTagsPreserved {
 [CmdletBinding()]
 param([AllowNull()][object]$Before,[AllowNull()][object]$After,[switch]$FormatTags)
 $sets=@()
 foreach($tags in @($Before,$After)){
  $map=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
  if($null -ne $tags){
   if($tags -isnot [pscustomobject]){throw [IO.InvalidDataException]::new('Tags devem ser objeto JSON')}
   foreach($property in $tags.PSObject.Properties){
    if($FormatTags -and [string]::Equals($property.Name,'marcador_coletanea',[StringComparison]::Ordinal)){continue}
    if($property.Value -isnot [string]){throw [IO.InvalidDataException]::new('Tag sem valor textual: '+$property.Name)}
    $map.Add($property.Name,$property.Value)
   }
  }
  $sets+=,$map
 }
 if($sets[0].Count -ne $sets[1].Count){throw [IO.InvalidDataException]::new('Conjunto de tags alterado')}
 foreach($key in $sets[0].Keys){
  if(-not $sets[1].ContainsKey($key) -or -not [string]::Equals($sets[0][$key],$sets[1][$key],[StringComparison]::Ordinal)){
   throw [IO.InvalidDataException]::new('Tag alterada: '+$key)
  }
 }
 return $true
}

# Validacao por leitura; o chamador ainda deve publicar e atualizar estado com seguranca.
function Assert-Mp3MarkerCandidate {
 [CmdletBinding()]
 param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$File,
       [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Candidate,
       [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$Marker)
 foreach($path in @($File,$Candidate)){
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){throw [IO.FileNotFoundException]::new('Arquivo ausente',$path)}
 }
 $sourcePath=[IO.Path]::GetFullPath($File);$candidatePath=[IO.Path]::GetFullPath($Candidate)
 $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
 if([string]::Equals($sourcePath,$candidatePath,$comparison)){throw [ArgumentException]::new('Candidato deve diferir da fonte')}
 $normalized=ConvertTo-CollectionMarker -Value $Marker
 if([string]::IsNullOrEmpty($normalized)){throw [ArgumentException]::new('Marcador vazio')}
 $sourceHash=(Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash
 $candidateHash=(Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash
 $sourcePayload=Get-CompressedAudioHash -File $sourcePath -Ffmpeg $script:Ffmpeg
 $candidatePayload=Get-CompressedAudioHash -File $candidatePath -Ffmpeg $script:Ffmpeg
 if(-not [string]::Equals($sourcePayload,$candidatePayload,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Payload comprimido alterado')}
 $before=Get-AudioMetadataSnapshot -File $sourcePath -Ffprobe $script:Ffprobe
 $after=Get-AudioMetadataSnapshot -File $candidatePath -Ffprobe $script:Ffprobe
 if($before.format.format_name -cne 'mp3' -or $after.format.format_name -cne 'mp3'){throw [IO.InvalidDataException]::new('Formato deve ser MP3')}
 $oldMarker=[string]$before.format.tags.marcador_coletanea
 if(-not [string]::IsNullOrEmpty($oldMarker) -and -not [string]::Equals($oldMarker,$normalized,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Marcador existente nao pode ser sobrescrito')}
 if(-not [string]::Equals([string]$after.format.tags.marcador_coletanea,$normalized,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Marcador candidato divergente')}
 $null=Assert-MarkerTagsPreserved -Before $before.format.tags -After $after.format.tags -FormatTags
 $null=Assert-MarkerTagsPreserved -Before $before.streams[0].tags -After $after.streams[0].tags
 $beforeProbe=Probe-Audio -File $sourcePath
 $afterProbe=Probe-Audio -File $candidatePath
 if(-not (Test-FinalAudio -File $sourcePath -Probe $beforeProbe) -or -not (Test-FinalAudio -File $candidatePath -Probe $afterProbe)){throw [IO.InvalidDataException]::new('Audio nao atende ao contrato final')}
 foreach($probe in @($beforeProbe,$afterProbe)){
  foreach($key in @('duracao','bitrate_medido_kbps')){
   $value=[double]$probe[$key]
   if(-not [double]::IsFinite($value) -or $value -le 0){throw [IO.InvalidDataException]::new('Parametro medido invalido: '+$key)}
  }
 }
 foreach($key in @('codec','container','canais','amostragem','bitrate_medido_kbps','bitrate_nominal_bps','variacao_pacotes','lossless')){
  if(-not [object]::Equals($beforeProbe[$key],$afterProbe[$key])){throw [IO.InvalidDataException]::new('Parametro alterado: '+$key)}
 }
 if([Math]::Abs($beforeProbe.duracao-$afterProbe.duracao) -gt 0.001){throw [IO.InvalidDataException]::new('Parametro duracao alterado')}
 if((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -cne $sourceHash -or (Get-FileHash -LiteralPath $candidatePath -Algorithm SHA256).Hash -cne $candidateHash){throw [IO.InvalidDataException]::new('Arquivo mudou durante validacao')}
 return [pscustomobject]@{Verified=$true;SourcePath=$sourcePath;CandidatePath=$candidatePath;SourceSha256=$sourceHash;CandidateSha256=$candidateHash;PayloadSha256=$sourcePayload;BeforeProbe=$beforeProbe;AfterProbe=$afterProbe}
}
