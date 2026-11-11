#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'manifesto_ffmpeg_bytes.ps1')
$script:Checks=0
function Assert($ok,$message){if(!$ok){throw $message};$script:Checks++}
$text=('a'*64)+'  ffmpeg-n9.0.2-48-gd4070a14ce-win64-lgpl-9.0.zip'+"`n"+('b'*64)+'  ffmpeg-n9.0.2-48-gd4070a14ce-winarm64-lgpl-9.0.zip'
$bytes=[Text.UTF8Encoding]::new($false,$true).GetBytes($text)
# Vetores SHA256 calculados independentemente antes da implementacao; dados sinteticos.
$sha='6e7880d9744869709c75f37656b86d1974748968e53a892c9160ab7a7534b625'
$base=@{Bytes=$bytes;ExpectedSize=[long]230;ExpectedSha256=$sha}
function ExpectError([hashtable]$changes,[type]$Expected){
    $call=$base.Clone();foreach($key in $changes.Keys){$call[$key]=$changes[$key]}
    $problem=$null;try{$null=ConvertFrom-CheckedFfmpegManifest @call}catch{$problem=$_}
    Assert ($null -ne $problem) 'Esperava rejeicao'
    $exception=$problem.Exception
    while($null -ne $exception -and !$Expected.IsInstanceOfType($exception)){$exception=$exception.InnerException}
    Assert ($null -ne $exception) ('Tipo de erro incorreto: '+$Expected.FullName)
}
Assert ($bytes.Length -eq 230) 'Vetor de bytes alterado'
$r=ConvertFrom-CheckedFfmpegManifest @base
Assert ($r -is [hashtable] -and $r.Count -eq 2) 'Retorno deve ser mapa unico de2campos'
Assert ($r.text -is [string] -and $r.text -ceq $text) 'Decodificacao alterou o manifesto'
Assert ($r.sha256 -is [string] -and $r.sha256 -ceq $sha) 'Hash calculado incorreto'
foreach($bad in @(
    @{Bytes=$null},@{Bytes=$text},@{Bytes=[int[]]$bytes},@{Bytes=[byte[]]@()},
    @{ExpectedSize='230'},@{ExpectedSize=[long]0},@{ExpectedSize=[long]1048577},@{ExpectedSize=[long]231},
    @{ExpectedSha256=$null},@{ExpectedSha256=$sha.ToUpperInvariant()},@{ExpectedSha256=('0'*64)}
)){ExpectError $bad ([ArgumentException])}
$tampered=[byte[]]$bytes.Clone();$tampered[0]=$tampered[0] -bxor 1
ExpectError @{Bytes=$tampered} ([ArgumentException])
# SHA confere para FF, mas UTF8 e invalido: deve chegar ao decoder estrito.
ExpectError @{Bytes=[byte[]](255);ExpectedSize=[long]1;ExpectedSha256='a8100ae6aa1940d0b663bb31cd466142ebbdbd5187131b92d93818987832eb89'} ([Text.DecoderFallbackException])
Write-Output "FFMPEG_MANIFEST_BYTES_PASS checks$script:Checks"
