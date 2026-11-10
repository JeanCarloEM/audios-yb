#requires -Version 7.0
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $repo 'candidato_ytdlp.ps1')
$work=Join-Path $PSScriptRoot ('.runtime-ytdlp-candidate-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($work)
$script:Checks=0;$script:ActionCalled=$false;$script:CandidatePath=''
function Assert($Ok,[string]$Why){if(-not $Ok){throw $Why};$script:Checks++}
function MustFail([scriptblock]$Call,[string]$Why){$failed=$false;try{$null=& $Call}catch{$failed=$true};Assert $failed $Why}
$foreign=Join-Path $work '.yt-dlp.candidate.foreign.exe';[IO.File]::WriteAllText($foreign,'preservar')
$result=Invoke-YtdlpCandidateFile -Root $work -Action {
 param($Path,$Stream)
 $script:ActionCalled=$true;$script:CandidatePath=$Path
 Assert ([IO.File]::Exists($Path) -and [IO.Path]::GetDirectoryName($Path) -ceq $work -and [IO.Path]::GetFileName($Path) -cmatch '\A\.yt-dlp\.candidate\.[0-9a-f]{32}\.exe\z') 'Criar candidato no Root antes de Action'
 Assert ($Stream -is [IO.FileStream] -and $Stream.CanWrite -and $Stream.CanRead) 'Action recebe stream proprio ReadWrite'
 $blocked=$false;try{$other=[IO.File]::OpenRead($Path);$other.Dispose()}catch [IO.IOException]{$blocked=$true}
 Assert $blocked 'Stream deve negar compartilhamento'
 $data=[Text.Encoding]::ASCII.GetBytes('abc');$Stream.Write($data,0,$data.Length);$Stream.Flush($true)
 return @{value='action-result'}
}
Assert ($script:ActionCalled -and $result -is [Collections.IDictionary] -and $result.value -ceq 'action-result') 'Retornar somente resultado da Action'
Assert (-not [IO.File]::Exists($script:CandidatePath) -and [IO.File]::ReadAllText($foreign) -ceq 'preservar') 'Limpeza propria no sucesso'
$script:CandidatePath=''
MustFail {Invoke-YtdlpCandidateFile -Root $work -Action {param($Path,$Stream);$script:CandidatePath=$Path;$Stream.Dispose();throw 'expected-action-failure'}} 'Propagar falha mesmo se Action fechar stream'
Assert (-not [IO.File]::Exists($script:CandidatePath)) 'Limpar candidato na falha'
$script:ActionCalled=$false
MustFail {Invoke-YtdlpCandidateFile -Root (Join-Path $work 'ausente') -Action {$script:ActionCalled=$true}} 'Nao criar Root implicitamente'
Assert (-not $script:ActionCalled -and -not [IO.Directory]::Exists((Join-Path $work 'ausente'))) 'Root ausente nao executa Action'
MustFail {Invoke-YtdlpCandidateFile -Root ' ' -Action {}} 'Root branco invalido'
MustFail {Invoke-YtdlpCandidateFile -Root $work -Action $null} 'Action obrigatoria sem prompt'
# Injeta somente a entropia; CreateNew e cleanup reais preservam outro escritor.
$t=$null;$e=$null;$a=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'candidato_ytdlp.ps1'),[ref]$t,[ref]$e)
$f=@($a.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Invoke-YtdlpCandidateFile'},$false))
$entropy="[guid]::NewGuid().ToString('N')"
if($e.Count -or $f.Count -ne 1 -or ([regex]::Matches($f[0].Extent.Text,[regex]::Escape($entropy))).Count -ne 1){throw 'Entropia nao unica'}
$probe=[regex]::Replace($f[0].Extent.Text,'\Afunction\s+Invoke-YtdlpCandidateFile\b','function Invoke-CandidateCollisionProbe')
if($probe -ceq $f[0].Extent.Text){throw 'Probe nao renomeado'}
. ([scriptblock]::Create($probe.Replace($entropy,"'00000000000000000000000000000001'")))
$null=Get-Command Invoke-CandidateCollisionProbe -CommandType Function -ErrorAction Stop
$collision=Join-Path $work '.yt-dlp.candidate.00000000000000000000000000000001.exe';[IO.File]::WriteAllText($collision,'outro escritor')
MustFail {Invoke-CandidateCollisionProbe -Root $work -Action {$script:ActionCalled=$true}} 'CreateNew recusa colisao'
Assert (-not $script:ActionCalled -and [IO.File]::ReadAllText($collision) -ceq 'outro escritor') 'Colisao nao autoriza Action ou limpeza alheia'
Assert (@(Get-ChildItem -LiteralPath $work -File).Count -eq 2) 'Sobrou arquivo proprio ou perdeu alheio'
$literal=Join-Path $work 'literal[1]';[void][IO.Directory]::CreateDirectory($literal)
$script:CandidatePath=''
Push-Location -LiteralPath $work
try{
 $result=Invoke-YtdlpCandidateFile -Root 'literal[1]' -Action {
  param($Path,$Stream)
  $script:CandidatePath=$Path
  Assert ([IO.Path]::IsPathRooted($Path) -and [IO.Path]::GetDirectoryName($Path) -ceq $literal) 'Root relativo vira absoluto, sem interpretar colchetes'
  return 'literal-result'
 }
}finally{Pop-Location}
Assert ($result -ceq 'literal-result' -and -not [IO.File]::Exists($script:CandidatePath)) 'Limpeza literal no Root com colchetes'
Assert (@(Get-ChildItem -LiteralPath $literal -Force).Count -eq 0) 'Candidato literal abandonado'
'YTDLP_CANDIDATE_LIFETIME_PASS checks'+$script:Checks+'; IO real sem rede/execucao; '+$work
