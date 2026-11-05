#requires -Version 7.0
$ErrorActionPreference='Stop'
Set-StrictMode -Version 1
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'execucao_unica.ps1')
function Assert($Condition,[string]$Reason){if(-not $Condition){throw $Reason}}
$id='TestVideo01'; $artist='AC/DC DJ'; $song='iTunes - ação'
$raw=@{VideoId=$id;ArtistaMusicaConferidos='SIM';VersaoConferida='SIM';SemVocaisConferido='SIM'}
$before=ConvertTo-Json $raw -Compress
Assert ($null -eq (Resolve-MusicalApprovalProof -VideoId $id -Artist $artist -Song $song)) 'Ausencia virou aprovacao'
$proof=Resolve-MusicalApprovalProof -VideoId $id -Artist $artist -Song $song -RawApproval $raw
Assert ($proof.versao -eq 1 -and $proof.video_id -ceq $id -and $proof.artista -ceq $artist -and $proof.musica -ceq $song) 'Identidade/protocolo alterados'
Assert ($proof.artista_musica_conferidos -is [bool] -and $proof.artista_musica_conferidos -and $proof.versao_conferida -and $proof.sem_vocais_conferido) 'Confirmacoes perdidas'
foreach($token in @('SIM',' s ','true','1')){
 $r=$raw.Clone()
 foreach($f in @('ArtistaMusicaConferidos','VersaoConferida','SemVocaisConferido')){$r[$f]=$token}
 Assert ($null -ne (Resolve-MusicalApprovalProof -VideoId $id -Artist $artist -Song $song -RawApproval $r -Origin interativo)) 'Alias aprovado rejeitado'
}
foreach($field in @('ArtistaMusicaConferidos','VersaoConferida','SemVocaisConferido')){
 foreach($value in @('NAO','0','',$null,$false)){
  $bad=$raw.Clone();$bad[$field]=$value
  Assert ($null -eq (Resolve-MusicalApprovalProof -VideoId $id -Artist $artist -Song $song -RawApproval $bad -StoredProof $proof)) ('Confirmacao ausente/falsa ignorada: '+$field)
 }
 $bad=$raw.Clone();[void]$bad.Remove($field)
 Assert ($null -eq (Resolve-MusicalApprovalProof -VideoId $id -Artist $artist -Song $song -RawApproval $bad)) 'Campo ausente aprovado'
}
$bad=$raw.Clone();$bad.VideoId='testVideo01'
Assert ($null -eq (Resolve-MusicalApprovalProof -VideoId $id -Artist $artist -Song $song -RawApproval $bad -StoredProof $proof)) 'ID case-sensitive ignorado'
$again=Resolve-MusicalApprovalProof -VideoId $id -Artist $artist -Song $song -StoredProof $proof
Assert ($null -ne $again -and -not [object]::ReferenceEquals($again,$proof)) 'Reuso nao devolve copia'
$again.musica='outra'
Assert ($proof.musica -ceq $song) 'Reuso alterou registro original'
foreach($field in @('artista_musica_conferidos','versao_conferida','sem_vocais_conferido')){
 foreach($value in @('true',1,$false,$null)){
  $bad=$proof.Clone();$bad[$field]=$value
  Assert ($null -eq (Resolve-MusicalApprovalProof -VideoId $id -Artist $artist -Song $song -StoredProof $bad)) 'Prova persistida coagiu flag nao booleana'
 }
}
foreach($item in @(@{field='versao';value=2},@{field='versao';value='1'},@{field='video_id';value='testVideo01'},@{field='artista';value='outro'},@{field='musica';value='outra'},@{field='origem';value='metadados'})){
 $bad=$proof.Clone();$bad[$item.field]=$item.value
 Assert ($null -eq (Resolve-MusicalApprovalProof -VideoId $id -Artist $artist -Song $song -StoredProof $bad)) 'Registro inconsistente aceito'
}
Assert ((ConvertTo-Json $raw -Compress) -ceq $before) 'Entrada alterada'
Assert ($null -eq (Resolve-MusicalApprovalProof -VideoId 'invalido' -Artist $artist -Song $song -RawApproval $raw)) 'ID invalido aprovado'
'RCF_MUSICAL_PROOF_PASS: aprovacoes explicitas, tres confirmacoes, aliases, identidade exata, reuso e negativos; helper sem integracao'
