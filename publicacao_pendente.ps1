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
