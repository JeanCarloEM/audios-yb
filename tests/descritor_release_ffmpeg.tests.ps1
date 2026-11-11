#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'descritor_release_ffmpeg.ps1')
$script:Checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:Checks++}
$tag='autobuild-2026-11-10-12-39'
# Nomes publicados; hashesZIP/tamanhosZIP sinteticos, sem bytes de executaveis.
# https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/tag/autobuild-2026-11-10-12-39
$x='ffmpeg-n9.0.2-48-gd4070a14ce-win64-lgpl-9.0.zip'
$a='ffmpeg-n9.0.2-48-gd4070a14ce-winarm64-lgpl-9.0.zip'
$text=('a'*64)+'  '+$x+"`n"+('b'*64)+'  '+$a
$bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes($text)
# Vetor SHA256 do manifesto230bytes calculado independentemente antes da implementacao.
$manifestSha='6e7880d9744869709c75f37656b86d1974748968e53a892c9160ab7a7534b625'
Assert ($bytes.Length -eq 230) 'Fixture de manifesto alterada'
$meta=@{tag_name=$tag;draft=$false;prerelease=$false;assets=@(
    @{name='checksums.sha256';size=230;digest=('sha256:'+$manifestSha)},
    @{name=$x;size=10;digest=('sha256:'+('a'*64))},
    @{name=$a;size=12;digest=('sha256:'+('b'*64))}
)}
$json=$meta|ConvertTo-Json -Depth 8
$base=@{Json=$json;ExpectedTag=$tag;ManifestBytes=$bytes;Architecture='X64'}
function MustFail([hashtable]$changes){
    $call=$base.Clone();foreach($key in $changes.Keys){$call[$key]=$changes[$key]}
    $failed=$false;try{$null=Resolve-FfmpegReleaseDescriptor @call}catch{$failed=$true}
    Assert $failed 'Descritor inconsistente foi aceito'
}
foreach($expected in @(@{Architecture='X64';Name=$x;Size=10;Sha=('a'*64)},@{Architecture='Arm64';Name=$a;Size=12;Sha=('b'*64)})){
    $call=$base.Clone();$call.Architecture=$expected.Architecture
    $r=Resolve-FfmpegReleaseDescriptor @call
    Assert ($r -is [hashtable] -and $r.Count -eq 4) 'Retorno deve ter quatro campos'
    Assert ($r.release_plan -is [hashtable] -and $r.release_plan.asset_name -ceq $expected.Name -and $r.release_plan.release_tag -ceq $tag) 'Plano associado incorretamente'
    Assert ($r.release_plan.sha256 -ceq $expected.Sha) 'HashZIP nao corresponde ao manifesto'
    Assert ($r.archive_size -is [long] -and $r.archive_size -eq $expected.Size) 'TamanhoZIP incorreto'
    Assert ($r.manifest_size -is [long] -and $r.manifest_size -eq 230 -and $r.manifest_sha256 -ceq $manifestSha) 'Manifesto nao conferido'
}
foreach($changes in @(@{ExpectedTag=$tag.ToUpperInvariant()},@{ExpectedTag='autobuild-2026-11-09-12-42'},@{ManifestBytes=$null},@{ManifestBytes=$text},@{ManifestBytes=[byte[]]@()},@{ManifestBytes=[byte[]](1,2,3)},@{Architecture='x64'})){MustFail $changes}
foreach($change in @(
    @{Index=0;Key='size';Value=231},@{Index=0;Key='digest';Value=$null},@{Index=0;Key='digest';Value=('sha256:'+('c'*64))},
    @{Index=1;Key='size';Value=0},@{Index=1;Key='size';Value=536870913},
    @{Index=1;Key='digest';Value=$null},@{Index=1;Key='digest';Value=('sha256:'+('c'*64))}
)){
    $m=$json|ConvertFrom-Json -AsHashtable
    $m.assets[$change.Index][$change.Key]=$change.Value
    MustFail @{Json=($m|ConvertTo-Json -Depth 8)}
}
$m=$json|ConvertFrom-Json -AsHashtable;$m.assets=@($m.assets|Where-Object {$_.name -cne 'checksums.sha256'})
MustFail @{Json=($m|ConvertTo-Json -Depth 8)}
Write-Output "FFMPEG_RELEASE_DESCRIPTOR_PASS checks$script:Checks; documentos/fixtures sinteticas, nao bytesZIP"
