#requires -Version 7.0
param([string]$HelperPath='')
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$root=Split-Path -Parent $PSScriptRoot
if([string]::IsNullOrWhiteSpace($HelperPath)){$HelperPath=Join-Path $root 'argumentos_metatags_mp3.ps1'}
$t=$null;$e=$null
$null=[Management.Automation.Language.Parser]::ParseFile($HelperPath,[ref]$t,[ref]$e)
if($e.Count){throw 'Sintaxe invalida'}
. $HelperPath
$base=Join-Path $root ('tests/.runtime-argv-noio-'+[guid]::NewGuid().ToString('N'))
$src=Join-Path $base 'origem [1].mp3'
$dst=Join-Path $base 'candidato.mp3'
$prefix=@('-nostdin','-v','error','-protocol_whitelist','file','-i',$src,'-map','0:a:0','-map_metadata','0','-c:a','copy','-id3v2_version','3')
$tail=@('-n',$dst)
$failed=0;$total=0
function Assert-Argv($Actual,[string[]]$Expected){
 if($Actual -isnot [string[]] -or $Actual.Count -ne $Expected.Count){throw 'Tipo ou quantidade de argv divergente'}
 for($i=0;$i -lt $Expected.Count;$i++){if(-not [string]::Equals($Actual[$i],$Expected[$i],[StringComparison]::Ordinal)){throw ('Argumento divergente: '+$i)}}
}
function Check-Positive([string]$Name,[scriptblock]$Body){
 $script:total++
 try{. $Body;'PASS '+$Name}catch{$script:failed++;'FAIL '+$Name+': '+$_.Exception.Message}
}
# Expectativas literais do contrato e do probe6e3f873f; nao calculadas pelo helper.
Check-Positive 'valid_order_and_values' {
 $u=@{composer='AC/DC';track='003';album='Álbum';title=' Faixa iTunes ';artist='Artista é DJ'}
 $got=New-Mp3EditorialTagArguments -SourcePath $src -CandidatePath $dst -Updates $u
 Assert-Argv $got ($prefix+@('-metadata','artist=Artista é DJ','-metadata','title= Faixa iTunes ','-metadata','album=Álbum','-metadata','track=003','-metadata','composer=AC/DC')+$tail)
 if($u.title -cne ' Faixa iTunes ' -or $u.Count -ne 5){throw 'Updates alterado'}
}
Check-Positive 'shelllike_data' {
 $v='x; $(boom) -i https://example.invalid " fim'
 $got=New-Mp3EditorialTagArguments -SourcePath $src -CandidatePath $dst -Updates @{title=$v}
 Assert-Argv $got ($prefix+@('-metadata',('title='+$v))+$tail)
}
Check-Positive 'canonical_paths' {
 $s=Join-Path $base 'pasta/../origem [1].mp3';$d=Join-Path $base 'pasta/../candidato.mp3'
 $got=New-Mp3EditorialTagArguments -SourcePath $s -CandidatePath $d -Updates @{title='X'}
 Assert-Argv $got ($prefix+@('-metadata','title=X')+$tail)
}
Check-Positive 'uppercase_extension' {
 $s=$src.Replace('.mp3','.MP3');$d=$dst.Replace('.mp3','.MP3')
 $p=$prefix.Clone();$p[6]=$s
 $got=New-Mp3EditorialTagArguments -SourcePath $s -CandidatePath $d -Updates @{title='X'}
 Assert-Argv $got ($p+@('-metadata','title=X','-n',$d))
}
Check-Positive 'ordinal_distinct_paths' {
 $s=Join-Path $base ('ti'+[char]0xAD+'tle.mp3');$d=Join-Path $base 'title.mp3'
 $p=$prefix.Clone();$p[6]=$s
 $got=New-Mp3EditorialTagArguments -SourcePath $s -CandidatePath $d -Updates @{title='X'}
 Assert-Argv $got ($p+@('-metadata','title=X','-n',$d))
}
$bad=@(
 @{Name='source_relative';Change=@{SourcePath='relative.mp3'}}
 @{Name='candidate_relative';Change=@{CandidatePath='relative.mp3'}}
 @{Name='source_null';Change=@{SourcePath=$null}}
 @{Name='source_empty';Change=@{SourcePath=''}}
 @{Name='source_whitespace';Change=@{SourcePath=' '}}
 @{Name='candidate_null';Change=@{CandidatePath=$null}}
 @{Name='candidate_empty';Change=@{CandidatePath=''}}
 @{Name='candidate_whitespace';Change=@{CandidatePath=' '}}
 @{Name='source_nul';Change=@{SourcePath=($src+[char]0)}}
 @{Name='candidate_nul';Change=@{CandidatePath=($dst+[char]0)}}
 @{Name='source_extension';Change=@{SourcePath=$src.Replace('.mp3','.m4a')}}
 @{Name='candidate_extension';Change=@{CandidatePath=$dst.Replace('.mp3','.wav')}}
 @{Name='same_path';Change=@{CandidatePath=$src}}
 @{Name='same_canonical_path';Change=@{CandidatePath=(Join-Path $base 'pasta/../origem [1].mp3')}}
 @{Name='updates_null';Change=@{Updates=$null}}
 @{Name='updates_empty';Change=@{Updates=@{}}}
 @{Name='unknown_key';Change=@{Updates=@{genre='X'}}}
 @{Name='case_key';Change=@{Updates=@{Title='X'}}}
 @{Name='ignorable_key';Change=@{Updates=@{('ti'+[char]0xAD+'tle')='X'}}}
 @{Name='non_string_key';Change=@{Updates=@{1='X'}}}
 @{Name='null_value';Change=@{Updates=@{title=$null}}}
 @{Name='integer_value';Change=@{Updates=@{title=3}}}
 @{Name='array_value';Change=@{Updates=@{title=@('A','B')}}}
 @{Name='empty_array_value';Change=@{Updates=@{title=@()}}}
 @{Name='whitespace_value';Change=@{Updates=@{title=(' '+[char]9)}}}
 @{Name='nul_value';Change=@{Updates=@{title=('A'+[char]0+'B')}}}
 @{Name='missing_updates';Change=@{};OmitUpdates=$true}
)
if($IsWindows){$bad+=@{Name='same_windows_case';Change=@{CandidatePath=$src.ToUpperInvariant()}}}else{
 Check-Positive 'case_distinct_non_windows' {
  $d=$src.ToUpperInvariant()
  $got=New-Mp3EditorialTagArguments -SourcePath $src -CandidatePath $d -Updates @{title='X'}
  Assert-Argv $got ($prefix+@('-metadata','title=X','-n',$d))
 }
}
foreach($c in $bad){
 $total++
 try{
  $call=@{SourcePath=$src;CandidatePath=$dst;Updates=@{title='X'}}
  foreach($key in $c.Change.Keys){$call[$key]=$c.Change[$key]}
  if($c.ContainsKey('OmitUpdates')){$call.Remove('Updates')}
  $caught=$false
  try{$null=New-Mp3EditorialTagArguments @call}catch{$ex=$_.Exception;while($null -ne $ex.InnerException){$ex=$ex.InnerException};if($ex -isnot [ArgumentException]){throw};$caught=$true}
  if(-not $caught){throw 'Entrada invalida foi aceita'}
  'PASS '+$c.Name
 }catch{$failed++;'FAIL '+$c.Name+': '+$_.Exception.Message}
}
if(Test-Path -LiteralPath $base){throw 'Builder criou arquivos/diretorio'}
if($failed){throw ('MP3_TAG_ARGV_FAILURES='+$failed)}
'MP3_TAG_ARGV_PASS cases='+$total
