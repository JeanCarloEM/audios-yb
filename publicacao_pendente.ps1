#requires -Version 7.0
# Snapshot de dados por leitura: NAO autoriza publicacao/recuperacao nem valida qualidade.
# Confinamento lexical; links simbolicos/identidade fisica devem ser verificados antes de I/O futuro.
function New-PublicationIntentSnapshot {
 [CmdletBinding()]
 param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Ready,
       [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Target,
       [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Control,
       [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Out,
       [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$VideoId,
       [Parameter(Mandatory)][hashtable]$Record,
       [Parameter(Mandatory)][hashtable]$Audit,
       [Parameter(Mandatory)][hashtable]$Probe)
 if($VideoId -cnotmatch '^[A-Za-z0-9_-]{11}$'){throw [ArgumentException]::new('VideoId invalido')}
 $controlPath=[IO.Path]::GetFullPath($Control)
 $outPath=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Out))
 foreach($path in @($controlPath,$outPath)){
  if(-not (Test-Path -LiteralPath $path -PathType Container)){throw [IO.DirectoryNotFoundException]::new('Diretorio ausente: '+$path)}
 }
 $readyPath=[IO.Path]::GetFullPath($Ready)
 $targetPath=[IO.Path]::GetFullPath($Target)
 if(-not (Test-Path -LiteralPath $readyPath -PathType Leaf)){throw [IO.FileNotFoundException]::new('Ready ausente',$readyPath)}
 $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
 if(-not [string]::Equals([IO.Path]::GetDirectoryName($targetPath),$outPath,$comparison)){throw [ArgumentException]::new('Target deve ser filho direto de Out')}
 if(Test-Path -LiteralPath $targetPath){throw [IO.IOException]::new('Target existente')}
 $relative=[IO.Path]::GetRelativePath($controlPath,$readyPath)
 if([IO.Path]::IsPathRooted($relative) -or $relative -ceq '..' -or $relative.StartsWith(('..'+[IO.Path]::DirectorySeparatorChar),[StringComparison]::Ordinal)){
  throw [ArgumentException]::new('Ready fora de Control')
 }
 foreach($key in @('chave','ordem','artista','musica','url_original','video_id')){
  if(-not $Record.ContainsKey($key) -or $Record[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($Record[$key])){throw [ArgumentException]::new('Record incompleto: '+$key)}
 }
 if(-not [string]::Equals($Record.video_id,$VideoId,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Record.video_id divergente')}
 $keyText=[string]::Join([char]31,@($Record.ordem.Trim(),$Record.artista.Trim(),$Record.musica.Trim(),$Record.url_original.Trim()))
 $hasher=[Security.Cryptography.SHA256]::Create()
 try{$keyBytes=$hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($keyText))}finally{$hasher.Dispose()}
 $keyHash=[BitConverter]::ToString($keyBytes).Replace('-','').ToLowerInvariant()
 if(-not [string]::Equals($Record.chave,$keyHash,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Record.chave divergente')}
 if(-not $Record.ContainsKey('aprovacao_musical') -or $Record.aprovacao_musical -isnot [hashtable] -or $Record.aprovacao_musical.Count -eq 0){throw [ArgumentException]::new('Aprovacao ausente')}
 if($Audit.validado -isnot [bool] -or -not $Audit.validado -or $Audit.politica -isnot [string] -or [string]::IsNullOrWhiteSpace($Audit.politica)){throw [ArgumentException]::new('Audit invalida')}
 foreach($key in @('origem_sha256','resultado_sha256')){
  if($Audit[$key] -isnot [string] -or $Audit[$key] -cnotmatch '^[0-9a-fA-F]{64}$'){throw [ArgumentException]::new('Hash invalido: '+$key)}
 }
 if($Probe.Count -eq 0){throw [ArgumentException]::new('Probe vazio')}
 $sizeBefore=(Get-Item -LiteralPath $readyPath).Length
 if($sizeBefore -le 0){throw [IO.InvalidDataException]::new('Ready vazio')}
 $hashBefore=(Get-FileHash -LiteralPath $readyPath -Algorithm SHA256).Hash.ToLowerInvariant()
 if(-not [string]::Equals($Audit.resultado_sha256.ToLowerInvariant(),$hashBefore,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Hash resultado divergente')}
 $data=@{registro=$Record;auditoria=$Audit;probe=$Probe}
 $copy=ConvertFrom-PublicationJson -Json ($data|ConvertTo-Json -Depth 25 -WarningAction Stop)
 $sizeAfter=(Get-Item -LiteralPath $readyPath).Length
 $hashAfter=(Get-FileHash -LiteralPath $readyPath -Algorithm SHA256).Hash.ToLowerInvariant()
 if($sizeBefore -ne $sizeAfter -or -not [string]::Equals($hashBefore,$hashAfter,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Ready mudou durante snapshot')}
 return @{
  schema='audios-yb-publication-intent/v1';status='preparada_nao_persistida';video_id=$VideoId
  pronto_relativo=$relative.Replace([IO.Path]::DirectorySeparatorChar,[char]'/')
  arquivo=[IO.Path]::GetFileName($targetPath);tamanho=$sizeBefore;sha256=$hashBefore
  registro=$copy.registro;auditoria=$copy.auditoria;probe=$copy.probe;criado_utc=[DateTime]::UtcNow.ToString('o')
 }
}

# Recusa reparse points existentes; nao promete imunidade a alteracoes externas concorrentes.
function Assert-PublicationPathWithoutLinks {
 param([Parameter(Mandatory)][string]$Path)
 $current=[IO.Path]::GetFullPath($Path)
 while(-not [string]::IsNullOrEmpty($current)){
  $item=Get-Item -LiteralPath $current -Force -ErrorAction Stop
  if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw [NotSupportedException]::new('Reparse point nao suportado: '+$current)}
  $current=[IO.Path]::GetDirectoryName([IO.Path]::TrimEndingDirectorySeparator($current))
 }
}

# Persistencia de dados apenas. Nenhuma autorizacao de mover audio ou restaurar State.
function Save-PublicationIntentFile {
 [CmdletBinding()]
 param([Parameter(Mandatory)][hashtable]$Snapshot,
       [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Control,
       [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Out)
 if(-not [string]::Equals([string]$Snapshot.schema,'audios-yb-publication-intent/v1',[StringComparison]::Ordinal) -or -not [string]::Equals([string]$Snapshot.status,'preparada_nao_persistida',[StringComparison]::Ordinal)){throw [ArgumentException]::new('Schema/status do snapshot invalido')}
 foreach($key in @('pronto_relativo','arquivo','criado_utc','sha256')){
  if($Snapshot[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($Snapshot[$key])){throw [ArgumentException]::new('Campo ausente: '+$key)}
 }
 if([IO.Path]::IsPathRooted($Snapshot.pronto_relativo) -or -not [string]::Equals([IO.Path]::GetFileName($Snapshot.arquivo),$Snapshot.arquivo,[StringComparison]::Ordinal)){throw [ArgumentException]::new('Caminho do snapshot invalido')}
 $controlPath=[IO.Path]::GetFullPath($Control)
 $outPath=[IO.Path]::GetFullPath($Out)
 $ready=[IO.Path]::GetFullPath([IO.Path]::Combine($controlPath,$Snapshot.pronto_relativo.Replace([char]'/',[IO.Path]::DirectorySeparatorChar)))
 $null=Assert-PublicationPathWithoutLinks -Path $controlPath
 $null=Assert-PublicationPathWithoutLinks -Path $outPath
 $null=Assert-PublicationPathWithoutLinks -Path $ready
 $fresh=New-PublicationIntentSnapshot -Ready $ready -Target (Join-Path $outPath $Snapshot.arquivo) -Control $controlPath -Out $outPath -VideoId $Snapshot.video_id -Record $Snapshot.registro -Audit $Snapshot.auditoria -Probe $Snapshot.probe
 if(-not [string]::Equals($Snapshot.pronto_relativo,$fresh.pronto_relativo,[StringComparison]::Ordinal) -or $Snapshot.tamanho -isnot [long] -and $Snapshot.tamanho -isnot [int]){throw [IO.InvalidDataException]::new('Dados de caminho/tamanho divergentes')}
 if($Snapshot.tamanho -ne $fresh.tamanho -or -not [string]::Equals($Snapshot.sha256,$fresh.sha256,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Hash/tamanho do snapshot divergente')}
 try{$created=[DateTimeOffset]::Parse($Snapshot.criado_utc,[Globalization.CultureInfo]::InvariantCulture)}catch{throw [ArgumentException]::new('Timestamp invalido')}
 if($created.Offset -ne [TimeSpan]::Zero){throw [ArgumentException]::new('Timestamp deve ser UTC')}
 $fresh.criado_utc=$Snapshot.criado_utc
 $fresh.status='preparada'
 $fresh.persistido_utc=[DateTime]::UtcNow.ToString('o')
 $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($fresh|ConvertTo-Json -Depth 25 -WarningAction Stop))
 if($bytes.Length -gt (Get-PublicationIntentMaxBytes)){throw [IO.InvalidDataException]::new('Intencao excede limite de bytes')}
 $sha=[Security.Cryptography.SHA256]::Create()
 try{
  $name=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($fresh.video_id))).Replace('-','').ToLowerInvariant()+'.json'
  $expectedHash=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()
 }finally{$sha.Dispose()}
 $directory=Join-Path $controlPath 'publicacoes_pendentes'
 if((Test-Path -LiteralPath $directory) -and -not (Test-Path -LiteralPath $directory -PathType Container)){throw [IO.IOException]::new('Diretorio de intencoes invalido')}
 $null=[IO.Directory]::CreateDirectory($directory)
 $null=Assert-PublicationPathWithoutLinks -Path $directory
 $path=Join-Path $directory $name
 if(Test-Path -LiteralPath $path){throw [IO.IOException]::new('Intencao existente preservada')}
 $temp=Join-Path $directory ('.'+[guid]::NewGuid().ToString('N')+'.tmp')
 $owned=$false
 try{
  $stream=[IO.FileStream]::new($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
  $owned=$true
  try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
  [IO.File]::Move($temp,$path)
 }finally{
  if($owned -and [IO.File]::Exists($temp)){[IO.File]::Delete($temp)}
 }
 if(-not [string]::Equals((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant(),$expectedHash,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Arquivo persistido divergente; evidencia preservada')}
 return @{Path=$path;Sha256=$expectedHash;Status='persistida_nao_autorizada'}
}

# Preserva strings ISO e chaves Ordinal; nao interpreta datas nem autoriza recuperacao.
function ConvertFrom-PublicationJson {
 [CmdletBinding()]
 param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Json)
 function Read-PublicationJsonNode([Text.Json.JsonElement]$Element) {
  switch($Element.ValueKind.ToString()){
   'Object' {
    $map=[hashtable]::new([StringComparer]::Ordinal)
    foreach($property in $Element.EnumerateObject()){
     if($map.ContainsKey($property.Name)){throw [IO.InvalidDataException]::new('JSON com chave duplicada: '+$property.Name)}
     $map.Add($property.Name,(Read-PublicationJsonNode -Element $property.Value))
    }
    return $map
   }
   'Array' {
    $items=[Collections.Generic.List[object]]::new()
    foreach($child in $Element.EnumerateArray()){$items.Add((Read-PublicationJsonNode -Element $child))}
    return ,($items.ToArray())
   }
   'String' {return $Element.GetString()}
   'Number' {
    $integer=[long]0
    if($Element.TryGetInt64([ref]$integer)){return $integer}
    $raw=$Element.GetRawText()
    if($raw.IndexOfAny([char[]]@('.','e','E')) -lt 0){throw [IO.InvalidDataException]::new('JSON inteiro fora de Int64')}
    try{$number=$Element.GetDouble()}catch{throw [IO.InvalidDataException]::new('JSON numero invalido')}
    if(-not [double]::IsFinite($number)){throw [IO.InvalidDataException]::new('JSON numero nao finito')}
    return $number
   }
   'True' {return $true}
   'False' {return $false}
   'Null' {return $null}
   default {throw [IO.InvalidDataException]::new('JSON valor nao suportado')}
  }
 }
 $options=[Text.Json.JsonDocumentOptions]::new()
 $options.MaxDepth=64
 try{$document=[Text.Json.JsonDocument]::Parse($Json,$options)}catch{throw [IO.InvalidDataException]::new('JSON invalido', $_.Exception)}
 try{
  if($document.RootElement.ValueKind -ne [Text.Json.JsonValueKind]::Object){throw [IO.InvalidDataException]::new('JSON raiz deve ser objeto')}
  return (Read-PublicationJsonNode -Element $document.RootElement)
 }finally{$document.Dispose()}
}

function Get-PublicationIntentMaxBytes { return 8388608 }

# Leitura de dados com hash externo. Nao valida qualidade/prova humana nem autoriza efeitos.
function Read-PublicationIntentFile {
 [CmdletBinding()]
 param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Path,
       [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ExpectedSha256,
       [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Control)
 if($ExpectedSha256 -cnotmatch '^[0-9a-f]{64}$'){throw [ArgumentException]::new('Hash esperado invalido')}
 $controlPath=[IO.Path]::GetFullPath($Control)
 $pathFull=[IO.Path]::GetFullPath($Path)
 $directory=Join-Path $controlPath 'publicacoes_pendentes'
 $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
 if(-not [string]::Equals([IO.Path]::GetDirectoryName($pathFull),$directory,$comparison)){throw [ArgumentException]::new('Arquivo fora do diretorio de intencoes')}
 if(-not (Test-Path -LiteralPath $pathFull -PathType Leaf)){throw [IO.FileNotFoundException]::new('Intencao ausente',$pathFull)}
 $null=Assert-PublicationPathWithoutLinks -Path $pathFull
 $stream=[IO.FileStream]::new($pathFull,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
 try{
  $length=$stream.Length
  if($length -le 0 -or $length -gt (Get-PublicationIntentMaxBytes)){throw [IO.InvalidDataException]::new('Tamanho do arquivo de intencao invalido')}
  $bytes=[byte[]]::new([int]$length)
  $offset=0
  while($offset -lt $bytes.Length){
   $count=$stream.Read($bytes,$offset,$bytes.Length-$offset)
   if($count -eq 0){throw [IO.InvalidDataException]::new('Arquivo de intencao truncado')}
   $offset+=$count
  }
  if($stream.ReadByte() -ne -1){throw [IO.InvalidDataException]::new('Arquivo de intencao cresceu')}
 }finally{$stream.Dispose()}
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$actual=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
 if(-not [string]::Equals($actual,$ExpectedSha256,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Hash do arquivo de intencao divergente')}
 try{$json=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)}catch{throw [IO.InvalidDataException]::new('UTF8 invalido')}
 $data=ConvertFrom-PublicationJson -Json $json
 if(-not [string]::Equals([string]$data.schema,'audios-yb-publication-intent/v1',[StringComparison]::Ordinal) -or -not [string]::Equals([string]$data.status,'preparada',[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Schema/status de intencao invalido')}
 if($data.video_id -isnot [string] -or $data.video_id -cnotmatch '^[A-Za-z0-9_-]{11}$'){throw [IO.InvalidDataException]::new('VideoId da intencao invalido')}
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$name=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($data.video_id))).Replace('-','').ToLowerInvariant()+'.json'}finally{$sha.Dispose()}
 if(-not [string]::Equals([IO.Path]::GetFileName($pathFull),$name,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Nome de arquivo nao corresponde ao VideoId')}
 foreach($key in @('registro','auditoria','probe')){
  if($data[$key] -isnot [hashtable] -or $data[$key].Count -eq 0){throw [IO.InvalidDataException]::new('Secao de dados invalida: '+$key)}
 }
 foreach($key in @('pronto_relativo','arquivo','criado_utc','persistido_utc','sha256')){
  if($data[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($data[$key])){throw [IO.InvalidDataException]::new('Campo de dados ausente: '+$key)}
 }
 if($data.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $data.tamanho -isnot [long] -and $data.tamanho -isnot [int] -or $data.tamanho -le 0){throw [IO.InvalidDataException]::new('Hash/tamanho de audio invalido')}
 if(-not [string]::Equals([string]$data.registro.video_id,$data.video_id,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Registro e VideoId divergentes')}
 # Metadados de caminhos/provas continuam pendentes de validacao antes de qualquer recuperacao.
 return @{Path=$pathFull;Sha256=$actual;Data=$data;Status='dados_lidos_nao_autorizados'}
}

# Plano por leitura; depende do executor/provas/evidencias atuais fornecidos pelo principal.
# O hash externo deve vir da referencia persistida pelo proprio fluxo, nao do arquivo lido.
function Get-PublicationRecoveryPlan {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedSha256,
       [Parameter(Mandatory)][string]$Control,[Parameter(Mandatory)][string]$Out)
 $loaded=Read-PublicationIntentFile -Path $Path -ExpectedSha256 $ExpectedSha256 -Control $Control
 $data=$loaded.Data;$record=$data.registro;$audit=$data.auditoria
 foreach($key in @('chave','ordem','artista','musica','url_original')){
  if($record[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($record[$key])){throw [IO.InvalidDataException]::new('Registro incompleto: '+$key)}
 }
 $keyText=[string]::Join([char]31,@($record.ordem.Trim(),$record.artista.Trim(),$record.musica.Trim(),$record.url_original.Trim()))
 $sha=[Security.Cryptography.SHA256]::Create()
 try{$key=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($keyText))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
 if(-not [string]::Equals($key,$record.chave,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Chave canonica do registro divergente')}
 if($record.aprovacao_musical -isnot [Collections.IDictionary]){throw [IO.InvalidDataException]::new('Aprovacao musical ausente')}
 $artist=$record.artista.Trim();$song=$record.musica.Trim()
 $proof=Resolve-MusicalApprovalProof -VideoId $data.video_id -Artist $artist -Song $song -StoredProof $record.aprovacao_musical
 if($null -eq $proof -or -not [string]::Equals([string]$proof.video_id,$data.video_id,[StringComparison]::Ordinal) -or -not [string]::Equals([string]$proof.artista,$artist,[StringComparison]::Ordinal) -or -not [string]::Equals([string]$proof.musica,$song,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Aprovacao musical invalida')}
 if($audit.validado -isnot [bool] -or -not $audit.validado -or -not [string]::Equals([string]$audit.politica,$script:Policy,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Politica de auditoria invalida')}
 if($audit.origem_sha256 -isnot [string] -or $audit.origem_sha256 -cnotmatch '^[0-9a-fA-F]{64}$' -or $audit.origem_formato_id -isnot [string] -or [string]::IsNullOrWhiteSpace($audit.origem_formato_id) -or $audit.origem -isnot [hashtable]){throw [IO.InvalidDataException]::new('Procedencia incompleta')}
 if(-not [string]::Equals(([string]$audit.resultado_sha256).ToLowerInvariant(),$data.sha256,[StringComparison]::Ordinal) -or $audit.origem.lossless -isnot [bool] -or -not [double]::IsFinite([double]$audit.origem.bitrate_medido_kbps) -or [double]$audit.origem.bitrate_medido_kbps -le 0){throw [IO.InvalidDataException]::new('Auditoria de origem/resultado divergente')}
 $sourceEvidence=Test-SourceEvidence -Id $data.video_id -FormatId $audit.origem_formato_id -Hash $audit.origem_sha256.ToLowerInvariant() -Probe $audit.origem
 if(-not $sourceEvidence.ok){throw [IO.InvalidDataException]::new('Procedencia atual nao confirmada: '+$sourceEvidence.motivo)}
 $controlPath=[IO.Path]::GetFullPath($Control);$outPath=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Out))
 if([IO.Path]::IsPathRooted($data.pronto_relativo) -or -not [string]::Equals([IO.Path]::GetFileName($data.arquivo),$data.arquivo,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Caminho de audio inseguro')}
 $ready=[IO.Path]::GetFullPath([IO.Path]::Combine($controlPath,$data.pronto_relativo.Replace([char]'/',[IO.Path]::DirectorySeparatorChar)))
 $relative=[IO.Path]::GetRelativePath($controlPath,$ready)
 if([IO.Path]::IsPathRooted($relative) -or $relative -ceq '..' -or $relative.StartsWith(('..'+[IO.Path]::DirectorySeparatorChar),[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Caminho Ready fora do controle')}
 $target=[IO.Path]::GetFullPath([IO.Path]::Combine($outPath,$data.arquivo))
 $null=Assert-PublicationPathWithoutLinks -Path $controlPath
 $null=Assert-PublicationPathWithoutLinks -Path $outPath
 if(Test-Path -LiteralPath $target){
  if(-not (Test-Path -LiteralPath $target -PathType Leaf)){throw [IO.InvalidDataException]::new('Destino existente nao e arquivo')}
  $chosen=$target;$action='restore_state'
 }elseif(Test-Path -LiteralPath $ready -PathType Leaf){$chosen=$ready;$action='publish'}
 else{throw [IO.FileNotFoundException]::new('Audio da intencao ausente',$ready)}
 $null=Assert-PublicationPathWithoutLinks -Path $chosen
 if((Get-Item -LiteralPath $chosen).Length -ne $data.tamanho -or -not [string]::Equals((Get-FileHash -LiteralPath $chosen).Hash.ToLowerInvariant(),$data.sha256,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Hash/tamanho do audio divergente')}
 $probe=Probe-Audio -File $chosen
 if(-not (Test-FinalAudio -File $chosen -Probe $probe)){throw [IO.InvalidDataException]::new('Qualidade final do audio reprovada')}
 foreach($key in @('codec','container','bitrate_nominal_bps')){
  if(-not [string]::Equals([string]$probe[$key],[string]$data.probe[$key],[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Parametro de audio divergente: '+$key)}
 }
 foreach($key in @('canais','amostragem')){
  if([long]$probe[$key] -ne [long]$data.probe[$key]){throw [IO.InvalidDataException]::new('Parametro de audio divergente: '+$key)}
 }
 foreach($key in @('lossless','variacao_pacotes')){
  if($data.probe[$key] -isnot [bool] -or $probe[$key] -ne $data.probe[$key]){throw [IO.InvalidDataException]::new('Parametro de audio divergente: '+$key)}
 }
 foreach($key in @('duracao','bitrate_medido_kbps')){
  $stored=[double]$data.probe[$key];$current=[double]$probe[$key]
  if(-not [double]::IsFinite($stored) -or -not [double]::IsFinite($current) -or $stored -le 0 -or $current -le 0 -or [Math]::Abs($stored-$current) -gt 0.001){throw [IO.InvalidDataException]::new('Parametro medido divergente: '+$key)}
 }
 if((Get-Item -LiteralPath $chosen).Length -ne $data.tamanho -or (Get-FileHash -LiteralPath $chosen).Hash.ToLowerInvariant() -cne $data.sha256 -or (Get-FileHash -LiteralPath $loaded.Path).Hash.ToLowerInvariant() -cne $ExpectedSha256){throw [IO.InvalidDataException]::new('Arquivo mudou durante plano')}
 return @{Status='plano_validado_sem_efeitos';Action=$action;Path=$chosen;Target=$target;Ready=$ready;IntentPath=$loaded.Path;IntentSha256=$ExpectedSha256;Data=$data;Probe=$probe;MusicalApproval=$proof;Artist=$artist;Song=$song;Evidence=$sourceEvidence}
}

# Requer o lock exclusivo adquirido pelo chamador. Mantem referencia ate State confirmado.
function Invoke-PublicationRecovery {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$ReferenceName,
       [Parameter(Mandatory)][string]$Control,[Parameter(Mandatory)][string]$Out)
 if($ReferenceName -cnotmatch '^[0-9a-f]{64}[.]json$'){throw [ArgumentException]::new('Nome de referencia invalido')}
 $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
 $controlPath=[IO.Path]::GetFullPath($Control);$outPath=[IO.Path]::GetFullPath($Out)
 if(-not [string]::Equals($controlPath,[IO.Path]::GetFullPath($script:Control),$comparison) -or -not [string]::Equals($outPath,[IO.Path]::GetFullPath($script:Out),$comparison) -or -not [string]::Equals([IO.Path]::GetFullPath($script:StateFile),(Join-Path $controlPath 'estado.json'),$comparison)){throw [ArgumentException]::new('Contexto de estado divergente')}
 if($script:Lock -isnot [IO.FileStream] -or -not $script:Lock.CanRead -or -not $script:Lock.CanWrite -or -not [string]::Equals($script:Lock.Name,(Join-Path $controlPath 'execucao.lock'),$comparison)){throw [InvalidOperationException]::new('Lock do destino requerido')}
 if(-not $script:State.ContainsKey('publicacoes_pendentes') -or -not $script:State.publicacoes_pendentes.ContainsKey($ReferenceName)){return @{Status='sem_pendencia';ReferenceName=$ReferenceName}}
 $reference=$script:State.publicacoes_pendentes[$ReferenceName]
 if($reference -isnot [hashtable] -or ($reference.versao -isnot [int] -and $reference.versao -isnot [long]) -or $reference.versao -ne 1){throw [IO.InvalidDataException]::new('Referencia de publicacao invalida')}
 foreach($key in @('arquivo','sha256','video_id','registro_chave')){
  if($reference[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($reference[$key])){throw [IO.InvalidDataException]::new('Referencia incompleta')}
 }
 if(-not [string]::Equals($reference.arquivo,$ReferenceName,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Referencia nao corresponde ao arquivo')}
 $null=Assert-PublicationPathWithoutLinks -Path $script:StateFile
 $disk=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile,[Text.UTF8Encoding]::new($false,$true)))
 if(-not $disk.ContainsKey('publicacoes_pendentes') -or -not $disk.publicacoes_pendentes.ContainsKey($ReferenceName)){throw [IO.InvalidDataException]::new('Referencia nao persistida')}
 $persisted=$disk.publicacoes_pendentes[$ReferenceName]
 foreach($key in @('versao','arquivo','sha256','video_id','registro_chave')){
  if(-not [string]::Equals([string]$persisted[$key],[string]$reference[$key],[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Referencia persistida divergente')}
 }
 $path=Join-Path (Join-Path $controlPath 'publicacoes_pendentes') $ReferenceName
 $plan=Get-PublicationRecoveryPlan -Path $path -ExpectedSha256 $reference.sha256 -Control $controlPath -Out $outPath
 $data=$plan.Data
 if(-not [string]::Equals($data.video_id,$reference.video_id,[StringComparison]::Ordinal) -or -not [string]::Equals($data.registro.chave,$reference.registro_chave,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Referencia e registro divergentes')}
 if($script:State.videos.ContainsKey($data.video_id)){
  $old=$script:State.videos[$data.video_id]
  if(-not [string]::Equals([string]$old.arquivo,$data.arquivo,[StringComparison]::Ordinal) -or -not [string]::Equals([string]$old.sha256,$data.sha256,[StringComparison]::Ordinal) -or -not [string]::Equals([string]$old.artista,$plan.Artist,[StringComparison]::Ordinal) -or -not [string]::Equals([string]$old.musica,$plan.Song,[StringComparison]::Ordinal) -or -not [string]::Equals([string]$old.aprovacao_musical.video_id,$data.video_id,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Conflito com video existente no estado')}
 }
 if((Get-FileHash -LiteralPath $plan.Path).Hash.ToLowerInvariant() -cne $data.sha256 -or (Get-Item -LiteralPath $plan.Path).Length -ne $data.tamanho -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne $reference.sha256){throw [IO.InvalidDataException]::new('Arquivo mudou antes da reconciliacao')}
 if($plan.Action -ceq 'publish'){
  $null=Assert-PublicationPathWithoutLinks -Path $plan.Ready
  $null=Assert-PublicationPathWithoutLinks -Path $outPath
  [IO.File]::Move($plan.Ready,$plan.Target)
 }elseif($plan.Action -cne 'restore_state'){throw [IO.InvalidDataException]::new('Acao de recuperacao invalida')}
 $null=Assert-PublicationPathWithoutLinks -Path $plan.Target
 if((Get-Item -LiteralPath $plan.Target).Length -ne $data.tamanho -or (Get-FileHash -LiteralPath $plan.Target).Hash.ToLowerInvariant() -cne $data.sha256){throw [IO.InvalidDataException]::new('Resultado publicado divergente; referencia preservada')}
 $now=[DateTime]::UtcNow.ToString('o')
 $audit=$data.auditoria
 $audit.resultado=$plan.Probe;$audit.evidencia=$plan.Evidence;$audit.aprovacao_musical=$plan.MusicalApproval
 $audit.recuperacao=@{acao=$plan.Action;intencao_sha256=$reference.sha256;verificado_utc=$now}
 $trace=$reference.Clone();$trace.situacao='concluida'
 $format=[IO.Path]::GetExtension($data.arquivo).TrimStart('.').ToLowerInvariant()
 $script:State.videos[$data.video_id]=@{artista=$plan.Artist;musica=$plan.Song;arquivo=$data.arquivo;tamanho=$data.tamanho;sha256=$data.sha256;formato=$format;codec=$plan.Probe.codec;bitrate_kbps=$plan.Probe.bitrate_medido_kbps;auditoria=$audit;aprovacao_musical=$plan.MusicalApproval;verificado_utc=$now;publicacao_intencao=$trace}
 $record=$data.registro
 $record.auditoria=$audit;$record.aprovacao_musical=$plan.MusicalApproval;$record.arquivo=$data.arquivo;$record.formato=$format;$record.codec=$plan.Probe.codec;$record.bitrate_kbps=[string]$plan.Probe.bitrate_medido_kbps
 $record.resultado=if($plan.Action -ceq 'publish'){'baixado'}else{'existente'}
 $record.motivo='Publicacao recuperada: identidade, evidencia e audio revalidados'
 $record.atualizado_utc=$now
 $script:State.registros[$record.chave]=$record
 # Primeiro confirmar video/registro mantendo a referencia; erro continua recuperavel.
 $null=Save-State
 $null=$script:State.publicacoes_pendentes.Remove($ReferenceName)
 $null=Save-State
 # JSON original e mantido como evidencia imutavel, referenciado pelo video concluido.
 return @{Status='reconciliada';Action=$plan.Action;VideoId=$data.video_id;RecordKey=$record.chave;Arquivo=$data.arquivo;Sha256=$data.sha256}
}

function Assert-PublicationContext {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$Control,[Parameter(Mandatory)][string]$Out)
 $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
 $controlPath=[IO.Path]::GetFullPath($Control);$outPath=[IO.Path]::GetFullPath($Out)
 if(-not [string]::Equals($controlPath,[IO.Path]::GetFullPath($script:Control),$comparison) -or -not [string]::Equals($outPath,[IO.Path]::GetFullPath($script:Out),$comparison) -or -not [string]::Equals([IO.Path]::GetFullPath($script:StateFile),(Join-Path $controlPath 'estado.json'),$comparison)){throw [ArgumentException]::new('Contexto de estado divergente')}
 if($script:Lock -isnot [IO.FileStream] -or -not $script:Lock.CanRead -or -not $script:Lock.CanWrite -or -not [string]::Equals($script:Lock.Name,(Join-Path $controlPath 'execucao.lock'),$comparison)){throw [InvalidOperationException]::new('Lock do destino requerido')}
}

# Confere apenas referencia persistida; nao autoriza mover audio nem certifica prova humana.
function Read-PersistedPublicationReference {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$ReferenceName,
       [Parameter(Mandatory)][string]$Control,[Parameter(Mandatory)][string]$Out)
 if($ReferenceName -cnotmatch '^[0-9a-f]{64}[.]json$'){throw [ArgumentException]::new('Nome de referencia invalido')}
 $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
 $controlPath=[IO.Path]::GetFullPath($Control);$outPath=[IO.Path]::GetFullPath($Out)
 if(-not [string]::Equals($controlPath,[IO.Path]::GetFullPath($script:Control),$comparison) -or -not [string]::Equals($outPath,[IO.Path]::GetFullPath($script:Out),$comparison) -or -not [string]::Equals([IO.Path]::GetFullPath($script:StateFile),(Join-Path $controlPath 'estado.json'),$comparison)){throw [ArgumentException]::new('Contexto de estado divergente')}
 if($script:Lock -isnot [IO.FileStream] -or -not $script:Lock.CanRead -or -not $script:Lock.CanWrite -or -not [string]::Equals($script:Lock.Name,(Join-Path $controlPath 'execucao.lock'),$comparison)){throw [InvalidOperationException]::new('Lock do destino requerido')}
 if(-not $script:State.ContainsKey('publicacoes_pendentes') -or -not $script:State.publicacoes_pendentes.ContainsKey($ReferenceName)){throw [IO.InvalidDataException]::new('Referencia nao persistida')}
 $reference=$script:State.publicacoes_pendentes[$ReferenceName]
 if($reference -isnot [hashtable] -or ($reference.versao -isnot [int] -and $reference.versao -isnot [long]) -or $reference.versao -ne 1){throw [IO.InvalidDataException]::new('Referencia de publicacao invalida')}
 foreach($key in @('arquivo','sha256','video_id','registro_chave')){
  if($reference[$key] -isnot [string] -or [string]::IsNullOrWhiteSpace($reference[$key])){throw [IO.InvalidDataException]::new('Referencia incompleta')}
 }
 if(-not [string]::Equals($reference.arquivo,$ReferenceName,[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Referencia nao corresponde ao arquivo')}
 $null=Assert-PublicationPathWithoutLinks -Path $script:StateFile
 $disk=ConvertFrom-PublicationJson -Json ([IO.File]::ReadAllText($script:StateFile,[Text.UTF8Encoding]::new($false,$true)))
 if(-not $disk.ContainsKey('publicacoes_pendentes') -or -not $disk.publicacoes_pendentes.ContainsKey($ReferenceName)){throw [IO.InvalidDataException]::new('Referencia nao persistida')}
 $persisted=$disk.publicacoes_pendentes[$ReferenceName]
 foreach($key in @('versao','arquivo','sha256','video_id','registro_chave')){
  if(-not [string]::Equals([string]$persisted[$key],[string]$reference[$key],[StringComparison]::Ordinal)){throw [IO.InvalidDataException]::new('Referencia persistida divergente')}
 }
  return $reference.Clone()
}

# Registra somente intencao existente validada; exige estado inicial salvo e nao move audio.
# O caller carrega referencia_publicacao.ps1. Validacoes/provas seguem o plano ja existente.
function Register-PublicationReference {
 [CmdletBinding()]
 param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedSha256,
       [Parameter(Mandatory)][string]$Control,[Parameter(Mandatory)][string]$Out)
 $null=Assert-PublicationContext -Control $Control -Out $Out
 if($script:State -isnot [hashtable]){throw [IO.InvalidDataException]::new('Estado invalido')}
 if($script:State.ContainsKey('publicacoes_pendentes') -and $script:State.publicacoes_pendentes -isnot [hashtable]){throw [IO.InvalidDataException]::new('Mapa de referencias invalido')}
 $plan=Get-PublicationRecoveryPlan -Path $Path -ExpectedSha256 $ExpectedSha256 -Control $Control -Out $Out
 $reference=New-PublicationReference -VideoId $plan.Data.video_id -RecordKey $plan.Data.registro.chave -IntentSha256 $ExpectedSha256
 if($script:State.ContainsKey('publicacoes_pendentes') -and $script:State.publicacoes_pendentes.ContainsKey($reference.arquivo)){throw [InvalidOperationException]::new('Referencia existente preservada')}
 $null=Assert-PublicationPathWithoutLinks -Path $script:StateFile
 if(-not $script:State.ContainsKey('publicacoes_pendentes')){$script:State.publicacoes_pendentes=@{}}
 $script:State.publicacoes_pendentes[$reference.arquivo]=$reference.Clone()
 $null=Save-State
 return (Read-PersistedPublicationReference -ReferenceName $reference.arquivo -Control $Control -Out $Out)
}
