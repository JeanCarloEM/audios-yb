#requires -Version 7.0
$ErrorActionPreference='Stop';$checks=0
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'authz_nativo_windows.ps1')
function Assert($ok,$why){if(!$ok){throw $why};$script:checks++}
Assert (@(Initialize-WindowsAuthzNative).Count -eq 0) 'Inicialização sem saída'
$assembly=[AudiosYb.Security.AuthzNativeV1.Luid].Assembly
$null=Initialize-WindowsAuthzNative
Assert ([object]::ReferenceEquals($assembly,[AudiosYb.Security.AuthzNativeV1.Luid].Assembly)) 'Tipos não recompilados'
$p=[IntPtr]::Size
$layouts=@(
 @{type=[AudiosYb.Security.AuthzNativeV1.Luid];size=8;fields=@('LowPart','HighPart');offsets=@(0,4);types=@([uint32],[int32])},
 @{type=[AudiosYb.Security.AuthzNativeV1.AccessRequest];size=$(if($p -eq 8){40}else{20});fields=@('DesiredAccess','PrincipalSelfSid','ObjectTypeList','ObjectTypeListLength','OptionalArguments');offsets=$(if($p -eq 8){@(0,8,16,24,32)}else{@(0,4,8,12,16)});types=@([uint32],[IntPtr],[IntPtr],[uint32],[IntPtr])},
 @{type=[AudiosYb.Security.AuthzNativeV1.AccessReply];size=$(if($p -eq 8){32}else{16});fields=@('ResultListLength','GrantedAccessMask','SaclEvaluationResults','Error');offsets=$(if($p -eq 8){@(0,8,16,24)}else{@(0,4,8,12)});types=@([uint32],[IntPtr],[IntPtr],[IntPtr])}
)
foreach($layout in $layouts){
 Assert ($layout.type.StructLayoutAttribute.Value -eq [Runtime.InteropServices.LayoutKind]::Sequential -and [Runtime.InteropServices.Marshal]::SizeOf([Activator]::CreateInstance($layout.type)) -eq $layout.size) ('Layout/tamanho: '+$layout.type.Name)
 for($i=0;$i -lt $layout.fields.Count;$i++){
  $field=$layout.type.GetField($layout.fields[$i]);Assert ($field.FieldType -eq $layout.types[$i] -and [Runtime.InteropServices.Marshal]::OffsetOf($layout.type,$field.Name).ToInt32() -eq $layout.offsets[$i]) ('Offset/tipo: '+$field.Name)
 }
}
Write-Output "AUTHZ_STRUCTS_LAYOUT_PASS checks=$checks; compilacao/layout apenas; nenhum PInvoke/token/UAC/ACL"
