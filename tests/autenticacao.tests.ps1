$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
$repo='D:\trampo\audios-yb'
. (Join-Path $repo 'autenticacao_ytdlp.ps1')
$t=$null;$e=$null
$a=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'baixar_audios_ytdlp.ps1'),[ref]$t,[ref]$e)
if($e.Count){throw 'Sintaxe principal invalida'}
foreach($name in @('Diagnose','Invoke-Checked')){
 $f=@($a.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true))
 if($f.Count -ne 1){throw 'Funcao principal ausente/ambigua'}
 Invoke-Expression $f[0].Extent.Text
}
function Assert($ok,$why){if(-not $ok){throw $why}}
$work=Join-Path $repo ('tests\.runtime-auth-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$p=Join-Path $work 'cookies de teste.txt'
foreach($header in @('# Netscape HTTP Cookie File','# HTTP Cookie File')){
 [IO.File]::WriteAllText($p,$header)
 $r=@(Get-YtdlpAuthArgs -CookiesArquivo $p)
 Assert ($r.Count -eq 2 -and $r[0] -eq '--cookies' -and $r[1] -ceq $p) 'Contrato arquivo invalido'
}
Assert (@(Get-YtdlpAuthArgs).Count -eq 0) 'Escolha automatica nao autorizada'
foreach($browser in @('chrome','firefox:perfil de teste')){
 $r=@(Get-YtdlpAuthArgs -CookiesNavegador $browser)
 Assert ($r.Count -eq 2 -and $r[0] -eq '--cookies-from-browser' -and $r[1] -ceq $browser) 'Descriptor argv invalido'
}
foreach($case in @('duplo','ausente','header','browser','perfil')){
 $failed=$false
 try{switch($case){
 duplo {Get-YtdlpAuthArgs -CookiesArquivo $p -CookiesNavegador chrome|Out-Null}
 ausente {Get-YtdlpAuthArgs -CookiesArquivo (Join-Path $work 'ausente')|Out-Null}
 header {[IO.File]::WriteAllText($p,'errado');Get-YtdlpAuthArgs -CookiesArquivo $p|Out-Null}
 browser {Get-YtdlpAuthArgs -CookiesNavegador 'invalido'|Out-Null}
 perfil {Get-YtdlpAuthArgs -CookiesNavegador 'chrome:'|Out-Null}
 }}catch{$failed=$true}
 Assert $failed ('Entrada invalida aceita: '+$case)
}
function Reset-Scenario($statuses,$answers,$noninteractive=$false){
 $script:AuthArgs=@();$script:AuthRecoveryAttempted=$false;$script:NetworkSuspended=$false
 $script:RateLimitStreak=0;$script:MaxTentativas=1;$script:NaoInterativo=$noninteractive
 $script:Calls=New-Object Collections.ArrayList
 $script:Statuses=New-Object Collections.Queue
 foreach($x in $statuses){$script:Statuses.Enqueue($x)}
 $script:Answers=New-Object Collections.Queue
 foreach($x in $answers){$script:Answers.Enqueue($x)}
 $script:Reads=0
}
function Read-InRunValue([string]$Prompt,[switch]$NonInteractive){
 if($NonInteractive -or $script:NaoInterativo){throw 'Leitura nao interativa proibida'}
 $script:Reads++
 if($script:Answers.Count -eq 0){throw 'Prompt extra inesperado'}
 return $script:Answers.Dequeue()
}
function Invoke-Ytdlp([string[]]$Arguments,[int]$TimeoutSeconds){
 [void]$script:Calls.Add(@($Arguments))
 if($script:Statuses.Count -eq 0){throw 'Chamada remota extra'}
 $s=$script:Statuses.Dequeue()
 if($s -eq 'ok'){return @{code=0;out='ok';err='';timeout=$false}}
 $err=switch($s){bot {"Sign in to confirm you're not a bot"};login {'Sign in required'};rate {'HTTP Error 429'};default {'error'}}
 return @{code=1;out='';err=$err;timeout=$false}
}
Reset-Scenario @('bot','ok','ok') @('navegador:chrome')
$r=Invoke-Checked @('--dump-single-json','https://www.youtube.com/watch?v=NBnH864JUZw') 20
Assert ($r.code -eq 0 -and $r.tentativas -eq 2 -and $script:Reads -eq 1 -and -not $script:NetworkSuspended) 'Recuperacao mesma chamada falhou'
Assert (($script:Calls[0] -join '|') -ceq '--dump-single-json|https://www.youtube.com/watch?v=NBnH864JUZw') 'Pedido original alterado'
Assert (($script:Calls[1] -join '|') -ceq '--cookies-from-browser|chrome|--dump-single-json|https://www.youtube.com/watch?v=NBnH864JUZw') 'Auth retry argv incorreto'
$r=Invoke-Checked @('--get-id','URL') 20
Assert ($r.code -eq 0 -and $script:Reads -eq 1 -and $script:Calls[2][1] -eq 'chrome') 'Auth nao reutilizada'
Reset-Scenario @('bot','bot') @('navegador:chrome')
$r=Invoke-Checked @('URL') 20
Assert ($r.code -ne 0 -and $script:Calls.Count -eq 2 -and $script:Reads -eq 1 -and $script:NetworkSuspended) 'Recuperacao ilimitada'
Reset-Scenario @('login') @('')
$r=Invoke-Checked @('URL') 20
Assert ($script:Calls.Count -eq 1 -and $script:NetworkSuspended) 'Cancelamento ignorado'
Reset-Scenario @('bot') @() $true
$r=Invoke-Checked @('URL') 20
Assert ($script:Reads -eq 0 -and $script:Calls.Count -eq 1 -and $script:NetworkSuspended) 'NaoInterativo ignorado'
Reset-Scenario @('ok') @() $true
$script:AuthArgs=@('--cookies-from-browser','chrome')
$r=Invoke-Checked @('URL') 20
Assert ($r.code -eq 0 -and $script:Reads -eq 0 -and $script:Calls[0][1] -eq 'chrome') 'Auth explicita ignorada'
Reset-Scenario @('rate') @()
$script:RateLimitStreak=2
$r=Invoke-Checked @('URL') 20
Assert ($script:NetworkSuspended -and $script:Reads -eq 0 -and $script:RateLimitStreak -eq 3) '429 alterado'
'AUTH_PASS'
