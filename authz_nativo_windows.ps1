#requires -Version 7.0
function Initialize-WindowsAuthzNative {
    if (-not $IsWindows) { throw [PlatformNotSupportedException]::new("Tipos Authz exigem Windows.") }
    if ('AudiosYb.Security.AuthzNativeV1.Native' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
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
public sealed class RmHandle : SafeHandleZeroOrMinusOneIsInvalid {
    public RmHandle() : base(true) {}
    protected override bool ReleaseHandle() { return Native.AuthzFreeResourceManager(handle); }
}
public sealed class CtxHandle : SafeHandleZeroOrMinusOneIsInvalid {
    public CtxHandle() : base(true) {}
    protected override bool ReleaseHandle() { return Native.AuthzFreeContext(handle); }
}
public static class Native {
    [DllImport("authz.dll", ExactSpelling=true, SetLastError=true, CharSet=CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool AuthzInitializeResourceManager(uint flags, IntPtr callbackAccess, IntPtr callbackCompute, IntPtr callbackFree, string name, out RmHandle manager);
    [DllImport("authz.dll", ExactSpelling=true, SetLastError=true, CharSet=CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool AuthzInitializeContextFromToken(uint flags, SafeAccessTokenHandle token, RmHandle manager, IntPtr expiration, Luid identifier, IntPtr dynamicArgs, out CtxHandle context);
    [DllImport("authz.dll", ExactSpelling=true, SetLastError=true, CharSet=CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool AuthzAccessCheck(uint flags, CtxHandle context, ref AccessRequest request, IntPtr audit, [In] byte[] descriptor, IntPtr optionalDescriptors, uint optionalCount, ref AccessReply reply, IntPtr cachedResultPointer);
    [DllImport("authz.dll", ExactSpelling=true, SetLastError=true, CharSet=CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool AuthzFreeContext(IntPtr context);
    [DllImport("authz.dll", ExactSpelling=true, SetLastError=true, CharSet=CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool AuthzFreeResourceManager(IntPtr manager);
}
}
'@
}
