#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'verificacao_candidato_ytdlp.ps1')
$work=Join-Path $PSScriptRoot ('.runtime-ytdlp-check-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$file=Join-Path $work 'candidate[1].exe';[IO.File]::WriteAllBytes($file,[Text.Encoding]::ASCII.GetBytes('abc'))
$hash='ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad'
$script:Checks=0;$script:Calls=0;$script:ActionCalled=$false;$script:ThrowNative=$false
$script:Native=@{code=0;out="v1`r`n";timeout=$false;err=''}
function Assert($Ok,[string]$Why){if(-not $Ok){throw $Why};$script:Checks++}
function MustFail([scriptblock]$Call,[string]$Why){$failed=$false;try{$null=& $Call}catch{$failed=$true};Assert $failed $Why}
function Locked($Path){
 $blocked=$false;$writer=$null
 try{$writer=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{$blocked=$true}finally{if($writer){$writer.Dispose()}}
 Assert $blocked 'Manter trava de leitura durante invocacao e Action'
}
function Released{
 $writer=[IO.File]::Open($file,[IO.FileMode]::Open,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None);$writer.Dispose()
 Assert $true 'Liberar handle antes de retornar ou propagar erro'
}
function Invoke-Ytdlp([string[]]$Arguments,[int]$TimeoutSeconds,[string]$Executable){
 $script:Calls++
 Assert ($Executable -ceq $file -and ($Arguments -join '|') -ceq '--ignore-config|--no-plugin-dirs|--version' -and $TimeoutSeconds -eq 15) 'Invocacao exata sem shell'
 Locked $Executable
 if($script:ThrowNative){throw 'expected-native-failure'}
 return $script:Native.Clone()
}
$r=Invoke-YtdlpVerifiedCandidate -Path $file -ExpectedSha256 $hash -ExpectedVersion 'v1' -Action {
 param($Version,$Path)
 $script:ActionCalled=$true;Assert ($Version -ceq 'v1' -and $Path -ceq $file) 'Action recebe versao/path conferidos'
 Locked $Path
 return @{value='checked-action'}
}
Assert ($script:Calls -eq 1 -and $script:ActionCalled -and $r -is [Collections.IDictionary] -and $r.value -ceq 'checked-action') 'Resultado da Action apos validacao'
Released
$script:Calls=0;$script:ActionCalled=$false
MustFail {Invoke-YtdlpVerifiedCandidate -Path $file -ExpectedSha256 ('0'*64) -ExpectedVersion 'v1' -Action {$script:ActionCalled=$true}} 'Rejeitar digest divergente'
Assert ($script:Calls -eq 0 -and -not $script:ActionCalled) 'Digest impede execucao/Action';Released
[IO.File]::WriteAllText($file,'changed')
MustFail {Invoke-YtdlpVerifiedCandidate -Path $file -ExpectedSha256 $hash -ExpectedVersion 'v1' -Action {$script:ActionCalled=$true}} 'Hash deve vir dos bytes atuais'
Assert ($script:Calls -eq 0 -and -not $script:ActionCalled) 'Bytes alterados impediram execucao';Released
[IO.File]::WriteAllBytes($file,[Text.Encoding]::ASCII.GetBytes('abc'))
foreach($bad in @(@{code=1;out='v1';timeout=$false},@{code=0;out='v1';timeout=$true},@{code=0;out='v2';timeout=$false},@{code=0;out='V1';timeout=$false},@{code=0;out='';timeout=$false})){
 $script:Native=$bad;$script:Calls=0;$script:ActionCalled=$false
 MustFail {Invoke-YtdlpVerifiedCandidate -Path $file -ExpectedSha256 $hash -ExpectedVersion 'v1' -Action {$script:ActionCalled=$true}} 'Native invalido impede Action'
 Assert ($script:Calls -eq 1 -and -not $script:ActionCalled) 'Nao ignorar erro/timeout/versao';Released
}
$script:Native=@{code=0;out='v1';timeout=$false};$script:ThrowNative=$true
try{MustFail {Invoke-YtdlpVerifiedCandidate -Path $file -ExpectedSha256 $hash -ExpectedVersion 'v1' -Action {}} 'Propagar erro do invocador'}finally{$script:ThrowNative=$false}
Released
MustFail {Invoke-YtdlpVerifiedCandidate -Path $file -ExpectedSha256 $hash -ExpectedVersion 'v1' -Action {throw 'expected-action-failure'}} 'Propagar erro da Action'
Released
Assert ((Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -ceq $hash) 'Nao alterar nem remover fonte'
'YTDLP_CANDIDATE_CHECK_PASS checks'+$script:Checks+'; IO real, invocador/Action simulados, sem execucao/rede; '+$work
