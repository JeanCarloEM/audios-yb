#requires -Version 7.0
function Initialize-WindowsAuthzNative {
    if (-not $IsWindows) { throw [PlatformNotSupportedException]::new("Tipos Authz exigem Windows.") }
    if ('AudiosYb.Security.AuthzNativeV1.Luid' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace AudiosYb.Security.AuthzNativeV1 {
[StructLayout(LayoutKind.Sequential)]
public struct Luid {
    public uint LowPart;
    public int HighPart;
}
[StructLayout(LayoutKind.Sequential)]
public struct AccessRequest {
    public uint DesiredAccess;
    public IntPtr PrincipalSelfSid;
    public IntPtr ObjectTypeList;
    public uint ObjectTypeListLength;
    public IntPtr OptionalArguments;
}
[StructLayout(LayoutKind.Sequential)]
public struct AccessReply {
    public uint ResultListLength;
    public IntPtr GrantedAccessMask;
    public IntPtr SaclEvaluationResults;
    public IntPtr Error;
}
}
'@
}
