#requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'instalacao_executavel_ffmpeg.ps1')
$script:extractionCalls=0
function Invoke-WithExtractedFfmpegCandidate { $script:extractionCalls++; throw 'Extração indevida' }
$checks=0
foreach($case in @(
 @{tool='FFMPEG';build='n9.0.2'},
 @{tool="ffmpeg`n";build='n9.0.2'},
 @{tool='ffmpeg';build='n9.0.2-49-gABCDEF0'},
 @{tool='ffmpeg';build='N9.0.2'}
)){
 $failed=$false
 try{$null=Install-FfmpegArchiveExecutable 'unused' $null 'ffmpeg-fixture' $case.tool $case.build {}}
 catch{$failed=$true}
 if(!$failed -or $script:extractionCalls -ne 0){throw 'Entrada inválida alcançou extração'}
 $checks++
}
$cancel=[Threading.CancellationTokenSource]::new()
try{
 $cancel.Cancel();$canceled=$false
 try{$null=Install-FfmpegArchiveExecutable 'unused' $null 'ffmpeg-fixture' 'ffmpeg' 'n9.0.2' {} -CancellationToken $cancel.Token}
 catch{if($_.Exception.GetBaseException() -is [OperationCanceledException]){$canceled=$true}else{throw}}
 if(!$canceled -or $script:extractionCalls -ne 0){throw 'Cancelamento não foi observado antes da extração'}
 $checks++
}finally{$cancel.Dispose()}
Write-Output "FFMPEG_ARCHIVE_GUARDS_PASS checks=$checks; extraction_calls=$script:extractionCalls"
