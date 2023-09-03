using module .\updater.psm1

using namespace System
using namespace System.IO
using namespace System.Text
using namespace System.Management.Automation

#Requires -Version 3.0

<#
.SYNOPSIS
Compiling PowerShell Class Modules into C# DLLs.

.DESCRIPTION
This script compiles PowerShell Class Modules into C# Dynamic Link Libraries (DLLs).
The compiled file can be imported into PowerShell using the "using assembly .\Path.dll" directive,
or utilized with other .NET languages such as C# by adding the DLL to references and importing it using "using static ExampleName;".

.PARAMETER Path
Specifies the path to the *.ps1 or *.psm1 script containing only a class and related namespaces.

.PARAMETER ScriptDefinition
Provides a string containing the class code.

.PARAMETER ModuleReferences
Adds a PowerShell package reference to the assembly. For instance, if "Compile-Dll" within your class has been utilized,
the reference must be included by adding "#include PSDllCompiler" at the beginning, or by using -ModuleReferences @("PSDllCompiler").

.PARAMETER OutputAssembly
Specifies the path where the resulting *.cs or *.dll file will be saved.

.PARAMETER DebugMode
Enables the GetPowershell() method, as well as access to both ClassHandlers and other features.

.EXAMPLE
Compile-Dll -Path .\example.psm1 -OutputAssembly .\example.dll

.EXAMPLE
Compile-Dll -Path .\example.psm1 -OutputAssembly .\example.cs

.EXAMPLE
$example = @'
class ExampleClass {
    ExampleClass() {}

    [string] $Name

    [string] SayHello() {
        
        return "Hello " + $this.Name
    }
}
'@
Compile-Dll -ScriptDefinition $example -OutputAssembly .\ExampleClass.dll
#>


function Compile-Dll {

    [CmdletBinding()]

    param (
        
        [string]$Path,

        [Parameter(ValueFromPipeline)]
        [string]$ScriptDefinition,

        [string[]]$ModuleReferences,

        [string]$OutputAssembly,

        [switch]$DebugMode
    )

    $ErrorActionPreference = [ActionPreference]::Stop

    #Update Check

    Write-Output "`nChecking for Updates...`n"

    if ([Updater]::UpdateAvailable()) {
        
        Write-Output "New update found!, use 'Update-Module PSDllCompiler'`n"

        foreach($i in 0..5) {
        
            Write-Output "Resuming in $(5 - $i)"
            Start-Sleep 1
            $i++
        }
    }

    if ($Path) {$Content = Get-Content $Path -Raw}
    elseif ($ScriptDefinition) {$Content = $ScriptDefinition}
    else {throw "Provide a input code using -Path or -ScriptDefinition !"}

    if (!$OutputAssembly) {throw "Provide a output path location using -OutputAssembly !"}

    $Content_Lines = $Content.Split("`n")

    Invoke-Expression $Content #Add Class

    foreach ($Class_Name in ($Content_Lines | Select-String "class" | Where-Object {!([string]$_).Contains("(")} | ForEach-Object {([string]$_).Split(" ")[1]})) {
        
        Write-Output "Compiling $Class_Name..."

        $Class_Constructors = Invoke-Expression "[$Class_Name].DeclaredConstructors" | Where-Object {$_.Name -eq ".ctor"}
        $Class_Methods = Invoke-Expression "[$Class_Name].DeclaredMethods" | Where-Object {!($_.Name.Contains("get_") -or $_.Name.Contains("set_"))}
        $Class_Properties = Invoke-Expression "[$Class_Name].DeclaredProperties"

        [string[]]$Class_Namespaces_CSharp = @("using System.Collections;", "using System.Management.Automation;", "using System.Text;")

        [string]$Class_Constructors_CSharp = ""
        [string]$Class_Methods_CSharp = ""
        [string]$Class_Properties_CSharp = ""

        [string]$Class_Handler_CSharp = ""
        [string]$Class_Static_Handler_CSharp = ""

        [string]$Class_CreatePowershell_CSharp = ""

        [hashtable[]]$Class_Handler_Properties = @()
        [hashtable[]]$Class_Static_Handler_Properties = @()

        [string]$Class_Powershell = ""
        [string]$References_Powershell = ""

        [string]$Class_Csharp = ""

#Powershell Class & Function References-----------------------------------------------------------
        
        $References_Powershell += '[string[]]$References_Module_b64 = @()' + "`n"

        $Content_Lines | Select-String "#include " -SimpleMatch | ForEach-Object {([string]$_).Replace("#include ", "").Split(",")} | ForEach-Object {$ModuleReferences += $_.Trim()}

        if ($PSVersionTable.PSVersion -ge [Version]"6.0") {$InstalledModules = Get-Command -Module ((Get-ChildItem "C:\Program Files\WindowsPowerShell\Modules").Name | Where-Object {$_ -notin @("PackageManagement", "PowerShellGet")})} #Powershell Core and it sux balls
        else {$InstalledModules = Get-Command -Module (Get-InstalledModule | Where-Object {$_.Name -notin @("PackageManagement", "PowerShellGet")}).Name} #Windows Powershell

        foreach ($command in $InstalledModules) {

            if ($Content -match $command.Name) {
                if ($command.ModuleName -cin $ModuleReferences) {
                    
                    Write-Output "    Adding $($command.ModuleName)..."

                    $module = Get-Item $command.Module.Path

                    $tmpfile = Join-Path $env:TMP ((New-Guid).Guid + ".zip")
                    Compress-Archive "$($module.DirectoryName)\*" $tmpfile -CompressionLevel Optimal -Force
                    $b64module = [Convert]::ToBase64String([File]::ReadAllBytes($tmpfile))

                    $References_Powershell += '$References_Module_b64 += "' + $b64module + '"' + "`n"
                }
                else {

                    [int[]]$line = ($Content_Lines | Select-String $command.Name).LineNumber
                    Write-Warning "at $($line -join ", "): $($command.Name) from $($command.ModuleName) is not referenced!"
                }
            } 
        }

        $References_Powershell += '
foreach ($b64module in $References_Module_b64) {

    $tmpfile = Join-Path $env:TMP ((New-Guid).Guid + ".zip")
    $tmpfolder = $tmpfile.Replace(".zip", "")
    Set-Content $tmpfile ([Convert]::FromBase64String($b64module)) -Encoding Byte
    Expand-Archive $tmpfile $tmpfolder
    (Get-Childitem "$tmpfolder\*.psd1").FullName | Foreach-Object {Import-Module ([string]$_)}
}'

        $Class_Powershell += $Content
        $Class_Powershell += "`n`n" + '$Global:Class = [' + "$Class_Name]`n"
        $Class_Powershell += '$Global:Class_Constructed = $null' + "`n`n"

#Class Constructors-------------------------------------------------------------------------------
        
        foreach ($constructor in $Class_Constructors) {

            [string]$CsConstructor = "    "

            $CsConstructor += "public $Class_Name ("
            $CsConstructor += "$([string]($constructor.GetParameters() -join ", ")))`n    {`n        "
            $CsConstructor += "object[] Arguments = { $([string]($constructor.GetParameters().Name -join ", ")) };`n`n        "
            $CsConstructor += "_ClassHandler($('"' + $Class_Name + '"'), Arguments);"
            $CsConstructor += "`n    }`n`n"

            $Class_Constructors_CSharp += $CsConstructor
        }

#Class Methods------------------------------------------------------------------------------------

        foreach ($method in $Class_Methods) {
            
            [string]$CsNamespace = ""
            
            $CsNamespace = "using $($method.ReturnType.Namespace);"
            if (!$Class_Namespaces_CSharp.Contains($CsNamespace)) {$Class_Namespaces_CSharp += $CsNamespace}

            [string]$CsMethod = "    "

            switch ($method) {
    
                {$_.IsPublic} {$CsMethod += "public "}
                {$_.IsPrivate} {$CsMethod += "private "}
                {$_.IsStatic} {$CsMethod += "static "}
            }
            $CsMethod += "$($method.ReturnType.Name) "
            $CsMethod += "$($method.Name) ("
            $CsMethod += "$([string]($method.GetParameters() -join ", ")))`n    {`n        "
            $CsMethod += "object[] Arguments = { $([string]($method.GetParameters().Name -join ", ")) };`n`n        "
            if ($method.IsStatic) {
                if ($method.ReturnType.Name -eq "void") {$CsMethod += "_StaticClassHandler($('"' + $method.Name + '"'), Arguments);"}
                else {$CsMethod += "return ($($method.ReturnType.Name))_StaticClassHandler($('"' + $method.Name + '"'), Arguments);"}
            }
            else {
                if ($method.ReturnType.Name -eq "void") {$CsMethod += "_ClassHandler($('"' + $method.Name + '"'), Arguments);"}
                else {$CsMethod += "return ($($method.ReturnType.Name))_ClassHandler($('"' + $method.Name + '"'), Arguments);"}
            }
            $CsMethod += "`n    }`n`n"
            $CsMethod = $CsMethod.Replace("Void", "void")

            $Class_Methods_CSharp += $CsMethod
        }

#Class Properties---------------------------------------------------------------------------------

        foreach ($property in $Class_Properties) {
            
            [string]$CsNamespace = ""

            $CsNamespace = "using $($property.PropertyType.Namespace);"
            if (!$Class_Namespaces_CSharp.Contains($CsNamespace)) {$Class_Namespaces_CSharp += $CsNamespace}

            [string]$CsProperty = ""

            ($Content_Lines | Select-String "hidden" -SimpleMatch).LineNumber | ForEach-Object {
                if ($_ -and ([string](($Content_Lines[($_ - 1)..$Content_Lines.Count] | Select-String "\$")[0]) -match ("$" + $property.Name))) {
                    $CsProperty += "    private "
                }
            }
            if (!$CsProperty) {$CsProperty += "    public "}
            if ($property.GetMethod.IsStatic -or $property.SetMethod.IsStatic) {
            
                $CsProperty += "static "

                $Class_Static_Handler_Properties += @{$property.Name = $property.PropertyType.Name}
            }
            else {$Class_Handler_Properties += @{$property.Name = $property.PropertyType.Name}}

            $CsProperty += "$($property.PropertyType.Name) $($property.Name) { get; set; }`n`n"

            $Class_Properties_CSharp += $CsProperty

            
        }

#_ClassHandler------------------------------------------------------------------------------------

        [string]$CsClassHandler = ""

        if ($DebugMode) {$CsClassHandler += "`n    public "}
        else {$CsClassHandler += "`n    private "}

        $CsClassHandler += 'object _ClassHandler(string Method, object[] Arguments)
    {
        if (_Powershell.Commands.Commands.Count == 0) { CreatePowershell(); }

        string Script = Encoding.UTF8.GetString(Convert.FromBase64String("cGFyYW0gKFtzdHJpbmddJE1ldGhvZCwgW29iamVjdFtdXSRBcmd1bWVudHMsIFtoYXNodGFibGVdJFByb3BlcnRpZXMsIFtib29sXSRJc1N0YXRpYykNCkNsYXNzSGFuZGxlciAtTWV0aG9kICRNZXRob2QgLUFyZ3VtZW50cyAkQXJndW1lbnRzIC1Qcm9wZXJ0aWVzICRQcm9wZXJ0aWVzIC1Jc1N0YXRpYyAkSXNTdGF0aWM="));

        Hashtable Properties = new Hashtable();'
        foreach ($property in $Class_Handler_Properties) {
        
            $CsClassHandler += "`n        Properties.Add($('"' + $property.Keys + '"'), $($property.Keys));`n"
        }
        $CsClassHandler += '
        _Powershell.Commands.Commands.Clear();
        _Powershell.AddScript(Script);
        _Powershell.AddArgument(Method);
        _Powershell.AddArgument(Arguments);
        _Powershell.AddArgument(Properties);
        _Powershell.AddArgument(false); //IsStatic

        Hashtable returnproperties = _Powershell.Invoke()[0].BaseObject as Hashtable;
    '
        foreach ($property in $Class_Handler_Properties) {
        
            $CsClassHandler += "`n        $($property.Keys) = ($($property.Values))returnproperties[$('"' + $property.Keys + '"')];"
        }
        $CsClassHandler += "`n`n        return returnproperties" + '["RETURN"];' + "`n    }`n`n"

        $Class_Handler_CSharp = $CsClassHandler

#_StaticClassHandler------------------------------------------------------------------------------

        [string]$CsStaticClassHandler = ""

        if ($DebugMode) {$CsStaticClassHandler += "`n    public "}
        else {$CsStaticClassHandler += "`n    private "}

        $CsStaticClassHandler += 'static object _StaticClassHandler(string Method, object[] Arguments)
    {
        if (_Powershell.Commands.Commands.Count == 0) { CreatePowershell(); }

        string Script = Encoding.UTF8.GetString(Convert.FromBase64String("cGFyYW0gKFtzdHJpbmddJE1ldGhvZCwgW29iamVjdFtdXSRBcmd1bWVudHMsIFtoYXNodGFibGVdJFByb3BlcnRpZXMsIFtib29sXSRJc1N0YXRpYykNCkNsYXNzSGFuZGxlciAtTWV0aG9kICRNZXRob2QgLUFyZ3VtZW50cyAkQXJndW1lbnRzIC1Qcm9wZXJ0aWVzICRQcm9wZXJ0aWVzIC1Jc1N0YXRpYyAkSXNTdGF0aWM="));

        Hashtable Properties = new Hashtable();'
        foreach ($property in $Class_Static_Handler_Properties) {
        
            $CsStaticClassHandler += "`n        Properties.Add($('"' + $property.Keys + '"'), $($property.Keys));`n"
        }
        $CsStaticClassHandler += '
        _Powershell.Commands.Commands.Clear();
        _Powershell.AddScript(Script);
        _Powershell.AddArgument(Method);
        _Powershell.AddArgument(Arguments);
        _Powershell.AddArgument(Properties);
        _Powershell.AddArgument(true); //IsStatic

        Hashtable returnproperties = _Powershell.Invoke()[0].BaseObject as Hashtable;
    '
        foreach ($property in $Class_Static_Handler_Properties) {
        
            $CsStaticClassHandler += "`n        $($property.Keys) = ($($property.Values))returnproperties[$('"' + $property.Keys + '"')];"
        }
        $CsStaticClassHandler += "`n`n        return returnproperties" + '["RETURN"];' + "`n    }`n"

        $Class_Static_Handler_CSharp = $CsStaticClassHandler

#CreatePowershell---------------------------------------------------------------------------------
        
        if ($DebugMode) {$Class_CreatePowershell_CSharp += "public "}
        else {$Class_CreatePowershell_CSharp += "private "}

        $Class_CreatePowershell_CSharp += 'static void CreatePowershell() 
    {
        string PlainRef = Encoding.UTF8.GetString(Convert.FromBase64String(_Base64Ref));
        string PlainClass = Encoding.UTF8.GetString(Convert.FromBase64String(_Base64Class));
        string ClassHandler = Encoding.UTF8.GetString(Convert.FromBase64String("ZnVuY3Rpb24gQ2xhc3NIYW5kbGVyIChbc3RyaW5nXSRNZXRob2QsIFtvYmplY3RbXV0kQXJndW1lbnRzLCBbaGFzaHRhYmxlXSRQcm9wZXJ0aWVzLCBbYm9vbF0kSXNTdGF0aWMpIHsNCiAgICANCiAgICBmdW5jdGlvbiBSZXR1cm5IYW5kbGVyIChbb2JqZWN0XSRSZXR1cm5WYWx1ZSwgW3N0cmluZ1tdXSRFeGlzdGluZ1Byb3BlcnRpZXMsIFtzd2l0Y2hdJElzU3RhdGljKSB7DQoNCiAgICAgICAgJHRhYmxlICs9IEB7UkVUVVJOID0gJFJldHVyblZhbHVlfQ0KDQogICAgICAgIGlmICgkSXNTdGF0aWMpIHsNCiAgICAgICAgICAgIGZvcmVhY2ggKCRwcm9wZXJ0eSBpbiAkRXhpc3RpbmdQcm9wZXJ0aWVzKSB7DQogICAgICAgICAgICAgICAgJHRhYmxlICs9IEB7JHByb3BlcnR5ID0gJENsYXNzOjokcHJvcGVydHl9DQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgZWxzZSB7DQogICAgICAgICAgICBmb3JlYWNoICgkcHJvcGVydHkgaW4gJEV4aXN0aW5nUHJvcGVydGllcykgew0KICAgICAgICAgICAgICAgICR0YWJsZSArPSBAeyRwcm9wZXJ0eSA9ICRHbG9iYWw6Q2xhc3NfQ29uc3RydWN0ZWQuJHByb3BlcnR5fQ0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgICAgIHJldHVybiAkdGFibGUNCiAgICB9DQoNCiAgICBpZiAoJElzU3RhdGljKSB7DQogICAgICAgIA0KICAgICAgICBpZiAoJFByb3BlcnRpZXMuR2V0RW51bWVyYXRvcigpLk1vdmVOZXh0KCkpIHsNCiAgICAgICAgICAgIGZvcmVhY2ggKCRwcm9wZXJ0eSBpbiAkUHJvcGVydGllcykgew0KICAgICAgICAgICAgICAgICRHbG9iYWw6Q2xhc3M6OigkcHJvcGVydHkuS2V5cykgPSAkcHJvcGVydHkuVmFsdWVzDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgaWYgKCRBcmd1bWVudHMgLWFuZCAkTWV0aG9kKSB7DQogICAgICAgICAgICAkcmV0dXJudmFsdWUgPSAkR2xvYmFsOkNsYXNzOjokTWV0aG9kLkludm9rZSgkQXJndW1lbnRzKQ0KICAgICAgICB9DQogICAgICAgIGVsc2VpZiAoJE1ldGhvZCkgew0KICAgICAgICAgICAgJHJldHVybnZhbHVlID0gJEdsb2JhbDpDbGFzczo6JE1ldGhvZCgpDQogICAgICAgIH0NCiAgICAgICAgUmV0dXJuSGFuZGxlciAtUmV0dXJuVmFsdWUgJHJldHVybnZhbHVlIC1FeGlzdGluZ1Byb3BlcnRpZXMgJFByb3BlcnRpZXMuS2V5cyAtSXNTdGF0aWMNCiAgICB9DQogICAgZWxzZWlmICgkTWV0aG9kIC1lcSAkR2xvYmFsOkNsYXNzLk5hbWUpIHsNCiAgICAgICAgaWYgKCRBcmd1bWVudHMpIHsNCiAgICAgICAgICAgICRHbG9iYWw6Q2xhc3NfQ29uc3RydWN0ZWQgPSBOZXctT2JqZWN0ICRHbG9iYWw6Q2xhc3MuTmFtZSAkQXJndW1lbnRzDQogICAgICAgIH0NCiAgICAgICAgZWxzZSB7DQogICAgICAgICAgICAkR2xvYmFsOkNsYXNzX0NvbnN0cnVjdGVkID0gTmV3LU9iamVjdCAkR2xvYmFsOkNsYXNzLk5hbWUNCiAgICAgICAgfQ0KICAgICAgICBSZXR1cm5IYW5kbGVyIC1SZXR1cm5WYWx1ZSAiTlVMTCIgLUV4aXN0aW5nUHJvcGVydGllcyAkUHJvcGVydGllcy5LZXlzDQogICAgfQ0KICAgIGVsc2Ugew0KICAgICAgICBpZiAoJFByb3BlcnRpZXMuR2V0RW51bWVyYXRvcigpLk1vdmVOZXh0KCkpIHsNCiAgICAgICAgICAgIGZvcmVhY2ggKCRwcm9wZXJ0eSBpbiAkUHJvcGVydGllcykgew0KICAgICAgICAgICAgICAgICRHbG9iYWw6Q2xhc3NfQ29uc3RydWN0ZWQuKCRwcm9wZXJ0eS5LZXlzKSA9ICRwcm9wZXJ0eS5WYWx1ZXMNCiAgICAgICAgICAgIH0gIA0KICAgICAgICB9ICAgIA0KICAgICAgICBpZiAoJEFyZ3VtZW50cyAtYW5kICRNZXRob2QpIHsNCiAgICAgICAgICAgICRyZXR1cm52YWx1ZSA9ICRHbG9iYWw6Q2xhc3NfQ29uc3RydWN0ZWQuJE1ldGhvZC5JbnZva2UoJEFyZ3VtZW50cykNCiAgICAgICAgfQ0KICAgICAgICBlbHNlaWYgKCRNZXRob2QpIHsNCiAgICAgICAgICAgICRyZXR1cm52YWx1ZSA9ICRHbG9iYWw6Q2xhc3NfQ29uc3RydWN0ZWQuJE1ldGhvZCgpDQogICAgICAgIH0NCiAgICAgICAgUmV0dXJuSGFuZGxlciAtUmV0dXJuVmFsdWUgJHJldHVybnZhbHVlIC1FeGlzdGluZ1Byb3BlcnRpZXMgJFByb3BlcnRpZXMuS2V5cw0KICAgIH0NCn0="));

        _Powershell.AddScript(PlainRef);
        _Powershell.AddScript(PlainClass);
        _Powershell.AddScript(ClassHandler);
        _Powershell.Invoke();
    }' + "`n`n"

#Finishing CSharp Class---------------------------------------------------------------------------
		
		[string]$CsClass = ""
		
		$CsClass += $Class_Namespaces_CSharp -join "`n"
		$CsClass += "`n`npublic class $Class_Name`n{`n    "
		$CsClass += "private static PowerShell _Powershell = PowerShell.Create();`n`n    "
		if ($DebugMode) {$CsClass += "public static object GetPowershell() { return _Powershell; }`n`n    "}
        if ($DebugMode) {$CsClass += "public "}
        else {$CsClass += "private "}
		$CsClass += 'static string _Base64Class = "' + [Convert]::ToBase64String([Encoding]::UTF8.GetBytes($Class_Powershell)) + '";' + "`n`n    "
        $CsClass += 'static string _Base64Ref = "' + [Convert]::ToBase64String([Encoding]::UTF8.GetBytes($References_Powershell)) + '";' + "`n`n    "
        $CsClass += $Class_CreatePowershell_CSharp

		$CsClass += $Class_Static_Handler_CSharp
		$CsClass += $Class_Handler_CSharp
        
        $CsClass += "    //Visible Class`n`n"

        $CsClass += $Class_Constructors_CSharp
		$CsClass += $Class_Properties_CSharp
		$CsClass += $Class_Methods_CSharp
		$CsClass += "}"

        $Class_Csharp += $CsClass
    }

#Writing Class_CSharp-----------------------------------------------------------------------------
    
    if ($OutputAssembly.Contains(".dll")) {
    
        Add-Type -TypeDefinition $Class_Csharp -OutputAssembly $OutputAssembly | Out-Null
    }
    elseif ($OutputAssembly.Contains(".cs")) {
        
        New-Item -Path $OutputAssembly -Value $Class_Csharp | Out-Null
    }

    Write-Output "`nSucesss, $((Get-Item $OutputAssembly).Name) has been compiled!"
}
