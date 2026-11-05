# ambiente_portatil.ps1 - Layout de script portátil
# Dot-source PS7+, descoberta de caminhos e CSV sem efeitos no lote

function Get-ScriptLayout([string]$ScriptPath) {
    if (-not [IO.File]::Exists($ScriptPath)) {
        throw "Script não encontrado: $ScriptPath"
    }

    $file = [IO.FileInfo]$ScriptPath
    $realPath = $file.FullName
    if (-not [string]::IsNullOrEmpty($file.LinkTarget)) {
        try {
            $resolved = $file.ResolveLinkTarget($true)
            if ($resolved -eq $null) {
                throw "Link não resolveu: $ScriptPath"
            }
            $realPath = $resolved.FullName
        } catch {
            throw "Falha ao resolver link: $ScriptPath - $($_.Exception.Message)"
        }
    }
    $root = [IO.Path]::GetDirectoryName($realPath)
    if ([string]::IsNullOrEmpty($root)) {
        throw "Não foi possível determinar o diretório raiz para: $ScriptPath"
    }
    $out = Join-Path $root "destino"
    $control = Join-Path $out ".controle"

    return @{
        Root    = $root
        Out     = $out
        Control = $control
    }
}

function Resolve-ScriptInput([string]$Path, [string]$Root) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "Caminho vazio ou nulo"
    }

    if ([IO.Path]::IsPathRooted($Path)) {
        return [IO.Path]::GetFullPath($Path)
    } else {
        return [IO.Path]::GetFullPath((Join-Path $Root $Path))
    }
}

function Get-ScriptCsvDelimiter([string]$Path) {
 $reader=[IO.StreamReader]::new($Path,[Text.Encoding]::UTF8,$true)
 try{$header=$reader.ReadLine()}finally{$reader.Dispose()}
 $required=@('Ordem','Artista','Musica','Link_YouTube','Tipo_link','Verificacao','Observacoes')
 if(-not [string]::IsNullOrWhiteSpace($header)){
  foreach($delimiter in @([char]',',[char]';',[char]9)){
   try{
    $probe=@(@($header,'__header_probe__')|ConvertFrom-Csv -Delimiter $delimiter -ErrorAction Stop)
    $columns=@($probe[0].PSObject.Properties.Name)
    if(@($required|Where-Object {$_ -cnotin $columns}).Count -eq 0){return $delimiter}
   }catch{continue}
  }
 }
 throw "CSV sem cabecalho valido (virgula, ponto e virgula ou tab): $Path"
}
function Find-ScriptCsv([string]$Root,[string]$Csv) {
 if(-not [IO.Directory]::Exists($Root)){throw "Diretorio raiz inexistente para CSV: $Root"}
 if(-not [string]::IsNullOrWhiteSpace($Csv)){
  $path=Resolve-ScriptInput -Path $Csv -Root $Root
  if(-not [IO.File]::Exists($path)){throw "CSV nao encontrado: $path"}
  return $path
 }
 $candidates=@(
  foreach($file in @(Get-ChildItem -LiteralPath $Root -Filter '*.csv' -File)){
   try{$null=Get-ScriptCsvDelimiter -Path $file.FullName;$file.FullName}catch{continue}
  }
 )
 if($candidates.Count -eq 0){throw "Nenhum CSV com cabecalho valido junto ao script: $Root"}
 if($candidates.Count -gt 1){throw "CSV ambiguo: $($candidates.Count) candidatos validos; informe -Csv com nome relativo."}
 return [IO.Path]::GetFullPath($candidates[0])
}
