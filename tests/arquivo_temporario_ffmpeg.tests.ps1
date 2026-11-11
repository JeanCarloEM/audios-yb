#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'arquivo_temporario_ffmpeg.ps1')
$script:Checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:Checks++}
function MustFail([scriptblock]$action){$failed=$false;try{$null=& $action}catch{$failed=$true};Assert $failed 'Entrada/falha do callback aceita'}
$fixture=Join-Path $PSScriptRoot ('.runtime-owned-ffmpeg-'+[guid]::NewGuid().ToString('N'))
$root=Join-Path $fixture 'root com espacos'
$keep=Join-Path $root 'keep.txt'
[void][IO.Directory]::CreateDirectory($root)
[IO.File]::WriteAllText($keep,'sentinela')
try{
 $script:Candidate=$null;$script:SavedStream=$null
 $result=Invoke-WithFfmpegArchiveStream -RootDirectory $root -Action {
  param($stream)
  $script:Candidate=$stream.Name;$script:SavedStream=$stream
  Assert ($stream -is [IO.FileStream] -and $stream.CanRead -and $stream.CanWrite -and $stream.CanSeek) 'Callback recebe FileStream proprio de leitura/escrita'
  Assert ([string]::Equals([IO.Path]::GetDirectoryName($stream.Name),$root,[StringComparison]::OrdinalIgnoreCase)) 'Arquivo somente no root fornecido'
  $stream.Write([byte[]]@(97,98,99),0,3);$stream.Position=0
  Assert ($stream.ReadByte() -eq 97) 'Permite escrita e rewind para ZIP futuro'
  $blocked=$false
  try{$other=[IO.File]::Open($stream.Name,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite);$other.Dispose()}catch [IO.IOException]{$blocked=$true}
  Assert $blocked 'Segundo handle bloqueado durante callback'
  return 'callback-ok'
 }
 Assert ($result -is [string] -and $result -ceq 'callback-ok') 'Propagar somente saida do callback'
 Assert (!$script:SavedStream.CanRead -and ![IO.File]::Exists($script:Candidate)) 'Fechar stream e excluir arquivo apos sucesso'
 $script:FailurePath=$null
 MustFail {Invoke-WithFfmpegArchiveStream -RootDirectory $root -Action {param($stream) $script:FailurePath=$stream.Name;throw 'callback-fail'}}
 Assert (![IO.File]::Exists($script:FailurePath)) 'Falha do callback tambem exclui somente proprio arquivo'
 Assert ([IO.File]::ReadAllText($keep) -ceq 'sentinela' -and [IO.Directory]::GetFiles($root).Count -eq 1) 'Arquivo preexistente preservado'
 $script:Called=0
 foreach($badRoot in @($null,123,'relative/path',(Join-Path $fixture 'missing'),$keep)){
  MustFail {Invoke-WithFfmpegArchiveStream -RootDirectory $badRoot -Action {$script:Called++}}
 }
 MustFail {Invoke-WithFfmpegArchiveStream -RootDirectory $root -Action $null}
 Assert ($script:Called -eq 0 -and [IO.Directory]::GetFiles($root).Count -eq 1) 'Entradas invalidas sem callback/novos arquivos'
}finally{
 # Exclusao nao recursiva: sobra inesperada faz o teste falhar e preserva evidencia.
 if([IO.File]::Exists($keep)){[IO.File]::Delete($keep)}
 [IO.Directory]::Delete($root,$false)
 [IO.Directory]::Delete($fixture,$false)
}
"FFMPEG_OWNED_STREAM_PASS checks$script:Checks; somente fixture propria, sem HTTP/ZIP/instalacao"
