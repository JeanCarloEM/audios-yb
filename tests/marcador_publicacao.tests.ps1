#requires -Version 7.0
param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$FixtureRoot)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$script:Root=$repo
$script:Exe=Join-Path $repo 'yt-dlp.exe'
$script:Ffmpeg=Join-Path $repo 'ffmpeg.exe'
$script:Ffprobe=Join-Path $repo 'ffprobe.exe'
$script:Policy='fidelidade-128-v1'
$script:Evidencias=@{}
. (Join-Path $repo 'editorial_audio.ps1')
$files=@((Join-Path $FixtureRoot 'fonte.mp3'),(Join-Path $FixtureRoot 'marcado.mp3'))
$hashes=@('ED90F05F84430C3C85A9E08BF6748BF42776001509F1827C288C9C18F81DC733','5C1CF6458DED20094404B77B73E857DBE2B916F94590D1A982FBBBB6A7EFE52A')
for($i=0;$i -lt 2;$i++){
 if((Get-FileHash -LiteralPath $files[$i]).Hash -cne $hashes[$i]){throw 'Fixture divergente'}
 $script:Evidencias['FixtureMP01|mp3-192|'+$hashes[$i].ToLowerInvariant()]=@{qualidade='perdas_verificadas';bitrate_minimo_historico_kbps=192;origem='Fixture sintetica local';historico='Ruido gerado e codificado uma unica vez como MP3; remux adicional somente para marcador'}
}
$marker='Minha colet'+[char]0x00E2+'nea'
$request=' MINHA COLET'+[char]0x00C2+'NEA '
$work=Join-Path $PSScriptRoot ('.runtime-marcador-publicacao-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $work
$cases=@(
 @{Name='legado';Index=0;Marker='';Status=''},
 @{Name='novo';Index=0;Marker=$request;Status='aplicado'},
 @{Name='igual';Index=1;Marker=$request;Status='ja_presente'},
 @{Name='conflito';Index=1;Marker='Outra';Status='limitacao'},
 @{Name='colisao';Index=0;Marker=$request;Status='colisao'}
)
foreach($case in $cases){
 $dir=Join-Path $work $case.Name
 $null=New-Item -ItemType Directory -Path $dir
 $source=Join-Path $dir 'fonte.mp3'
 Copy-Item -LiteralPath $files[$case.Index] -Destination $source
 $targetBase=Join-Path $dir 'final'
 $target=$targetBase+'.mp3'
 if($case.Status -ceq 'colisao'){Copy-Item -LiteralPath $files[1] -Destination $target}
 $result=Complete-Audio -Source $source -TargetBase $targetBase -Id 'FixtureMP01' -Fmt @{id='mp3-192';operacao='nativo';duracao_origem=2} -Marcador $case.Marker
 if($case.Status -ceq 'colisao'){
  if($result.ok -or (Get-FileHash -LiteralPath $target).Hash -cne $hashes[1] -or (Get-FileHash -LiteralPath $source).Hash -cne $hashes[0]){throw 'Colisao sobrescreveu arquivo'}
  continue
 }
 if(-not $result.ok -or $result.arquivo -cne 'final.mp3' -or -not $result.auditoria.validado){throw 'Publicacao falhou'}
 $finalHash=(Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant()
 if($result.auditoria.origem_sha256 -cne $hashes[$case.Index].ToLowerInvariant() -or $result.auditoria.resultado_sha256 -cne $finalHash){throw 'Auditoria confundiu hashes de origem/resultado'}
 if([string]::IsNullOrEmpty($case.Status)){
  if($finalHash -cne $hashes[0].ToLowerInvariant() -or $result.auditoria.ContainsKey('marcador')){throw 'Modo legado mudou bytes ou auditoria'}
  continue
 }
 if($result.auditoria.marcador.status -cne $case.Status){throw 'Status editorial incorreto'}
 $snapshot=Get-AudioMetadataSnapshot -File $target -Ffprobe $script:Ffprobe
 if(-not [string]::Equals([string]$snapshot.format.tags.marcador_coletanea,$marker,[StringComparison]::Ordinal)){throw 'Marcador final divergente'}
 $tags=@{artist='AC/DC';title='iTunes DJ';album='Album teste';track='12';composer='Autor teste';genre='Genero teste';comment='Comentario teste'}
 foreach($key in $tags.Keys){if(-not [string]::Equals([string]$snapshot.format.tags.$key,$tags[$key],[StringComparison]::Ordinal)){throw ('Tag final alterada: '+$key)}}
 if($case.Status -ceq 'aplicado'){
  if($result.auditoria.marcador.payload_sha256 -cne '0A11D18D8D81BF4A31A13C72CD7BBAA81B4C4D11A35B8DBAF0EA8EEA126C940F' -or (Get-FileHash -LiteralPath $source).Hash -cne $hashes[0]){throw 'Fonte ou payload nao preservado'}
 }elseif($finalHash -cne $hashes[1].ToLowerInvariant()){throw 'Audio existente foi reescrito'}
}
for($i=0;$i -lt 2;$i++){if((Get-FileHash -LiteralPath $files[$i]).Hash -cne $hashes[$i]){throw 'Fixture original alterada'}}
Write-Output 'MARCADOR_PUBLICACAO_PASS'
