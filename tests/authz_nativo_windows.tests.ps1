#requires -Version 7.0
$ErrorActionPreference='Stop';$checks=0
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'authz_nativo_windows.ps1')
function Assert($ok,$why){if(!$ok){throw $why};$script:checks++}
Assert (@(Initialize-WindowsAuthzNative).Count -eq 0) 'Inicialização não emite saída'
$native=[AudiosYb.Security.AuthzNativeV1.Native];$assembly=$native.Assembly
$null=Initialize-WindowsAuthzNative
Assert ([object]::ReferenceEquals($assembly,[AudiosYb.Security.AuthzNativeV1.Native].Assembly)) 'Tipos não recompilados'
$ns='AudiosYb.Security.AuthzNativeV1.'
# Contratos independentes: SDK Microsoft AuthZ.h; sem invocar funções importadas.
$signatures=@{
 AuthzInitializeResourceManager=@('System.UInt32','System.IntPtr','System.IntPtr','System.IntPtr','System.String',($ns+'RmHandle&'))
 AuthzInitializeContextFromToken=@('System.UInt32','Microsoft.Win32.SafeHandles.SafeAccessTokenHandle',($ns+'RmHandle'),'System.IntPtr',($ns+'Luid'),'System.IntPtr',($ns+'CtxHandle&'))
 AuthzAccessCheck=@('System.UInt32',($ns+'CtxHandle'),($ns+'AccessRequest&'),'System.IntPtr','System.Byte[]','System.IntPtr','System.UInt32',($ns+'AccessReply&'),'System.IntPtr')
 AuthzFreeContext=@('System.IntPtr')
 AuthzFreeResourceManager=@('System.IntPtr')
}
foreach($name in $signatures.Keys){
 $method=$native.GetMethod($name);$types=@($method.GetParameters()|ForEach-Object {$_.ParameterType.FullName})
 Assert (($types -join ',') -ceq ($signatures[$name] -join ',')) ('ABI exata: '+$name)
 $dll=@($method.GetCustomAttributes([Runtime.InteropServices.DllImportAttribute],$false))[0]
 Assert ($dll.Value -ceq 'authz.dll' -and $dll.ExactSpelling -and $dll.SetLastError -and $method.ReturnType -eq [bool]) ('Importação Win32: '+$name)
 $marshal=@($method.ReturnParameter.GetCustomAttributes([Runtime.InteropServices.MarshalAsAttribute],$false))
 Assert ($marshal.Count -eq 1 -and $marshal[0].Value -eq [Runtime.InteropServices.UnmanagedType]::Bool) ('BOOL4bytes: '+$name)
}
Assert (@($native.GetMethods([Reflection.BindingFlags]'Public,Static,DeclaredOnly')).Count -eq 5) 'Sem funções nativas adicionais'
Assert ($native.GetMethod('AuthzInitializeResourceManager').GetCustomAttributes([Runtime.InteropServices.DllImportAttribute],$false)[0].CharSet -eq [Runtime.InteropServices.CharSet]::Unicode) 'Nome do resource manager é Unicode'
Assert ($native.GetMethod('AuthzAccessCheck').GetParameters()[4].IsIn) 'Descritor é entrada byte[]'
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
foreach($type in @([AudiosYb.Security.AuthzNativeV1.RmHandle],[AudiosYb.Security.AuthzNativeV1.CtxHandle])){
 $handle=[Activator]::CreateInstance($type)
 Assert ($handle -is [Microsoft.Win32.SafeHandles.SafeHandleZeroOrMinusOneIsInvalid] -and $handle.IsInvalid) 'SafeHandle inicial inválido; sem recurso nativo'
 $handle.Dispose()
}
Write-Output "AUTHZ_ABI_LAYOUT_PASS checks=$checks; compilacao/reflexao/layout apenas, nenhuma chamada Authz/UAC/ACL"
