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
 $copy=ConvertFrom-Json -AsHashtable -InputObject ($data|ConvertTo-Json -Depth 25 -WarningAction Stop)
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
