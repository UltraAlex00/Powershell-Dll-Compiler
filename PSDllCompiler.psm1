using namespace System
using namespace System.Text

#Requires -Version 3.0

<# 
.SYNOPSIS
Compiles Powershell Class Modules into C# Dlls

.DESCRIPTION
Compiles Powershell Class Modules into C# Dlls.
The Compiled File can be imported by Powershell using "using assembly .\Path.dll"
or even with other .NET languages like C# by adding the dll
in references and importing it with "using static ExampleName;"

.PARAMETER Path
*.ps1 or *.psm1 script containing only a class and namespaces

.PARAMETER ScriptDefinition
a string containing the class code

.PARAMETER OutputAssembly
path where the *.cs or *.dll file will be saved

.PARAMETER DebugMode
Enables the GetPowershell() Method as well as access to both ClassHandlers and more

.EXAMPLE
Compile-Dll -Path .\example.psm1 -OutputAssembly .\example.dll

.EXAMPLE
Compile-Dll -Path .\example.psm1 -OutputAssembly .\example.cs

.EXAMPLE
$example = '
class ExampleClass {
    ExampleClass() {}

    [string] $Name

    [string] SayHello() {
        
        return "Hello" + $this.Name
    }
}
'
Compile-Dll -ScriptDefinition $example -OutputAssembly .\ExampleClass.dll
#>

function Compile-Dll {

    [CmdletBinding()]

    param (
        
        [string]$Path,

        [Parameter(ValueFromPipeline)]
        [string]$ScriptDefinition,

        [string]$OutputAssembly,

        [switch]$DebugMode
    )

    [Version]$Compiler_Version = "1.0.0"

    #Update Check

    Write-Output "`nChecking for Updates...`n"

    try {$Compiler_Version_Newest = (Find-Module "PSDllCompiler").Version}
    catch {
        
        Write-Output "Cannot reach update server!`n"
        $Compiler_Version_Newest = $Compiler_Version
    }    

    if ($Compiler_Version -lt $Compiler_Version_Newest) {
        
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
        
        Write-Output "`nCompiling $Class_Name..."

        $Class_Constructors += Invoke-Expression "[$Class_Name].DeclaredConstructors"
        $Class_Methods += Invoke-Expression "[$Class_Name].DeclaredMethods" | Where-Object {!($_.Name.Contains("get_") -or $_.Name.Contains("set_"))}

        $Class_Properties = Invoke-Expression "[$Class_Name].DeclaredProperties"

        [string[]]$Class_Namespaces_CSharp = @("using System.Collections;", "using System.Management.Automation;", "using System.Text;")

        [string]$Class_Constructors_CSharp = ""
        [string]$Class_Methods_CSharp = ""
        [string]$Class_Properties_CSharp = ""

        [string]$Class_Handler_CSharp = ""
        [string]$Class_Static_Handler_CSharp = ""

        [hashtable[]]$Class_Handler_Properties = @()
        [hashtable[]]$Class_Static_Handler_Properties = @()

        [string]$Class_Powershell = ""

        [string]$Class_Csharp = ""

#Powershell Class---------------------------------------------------------------------------------

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
            $CsMethod += "$($method.ReturnType) "
            $CsMethod += "$($method.Name) ("
            $CsMethod += "$([string]($method.GetParameters() -join ", ")))`n    {`n        "
            $CsMethod += "object[] Arguments = { $([string]($method.GetParameters().Name -join ", ")) };`n`n        "
            if ($method.IsStatic) {
                if ($method.ReturnType.Name -eq "Void") {$CsMethod += "_StaticClassHandler($('"' + $method.Name + '"'), Arguments);"}
                else {$CsMethod += "return ($($method.ReturnType))_StaticClassHandler($('"' + $method.Name + '"'), Arguments);"}
            }
            else {
                if ($method.ReturnType.Name -eq "Void") {$CsMethod += "_ClassHandler($('"' + $method.Name + '"'), Arguments);"}
                else {$CsMethod += "return ($($method.ReturnType))_ClassHandler($('"' + $method.Name + '"'), Arguments);"}
            }
            $CsMethod += "`n    }`n`n"

            $Class_Methods_CSharp += $CsMethod
        }

#Class Properties---------------------------------------------------------------------------------

        foreach ($property in $Class_Properties) {
            
            [string]$CsNamespace = ""

            $CsNamespace = "using $($property.PropertyType.Namespace);"
            if (!$Class_Namespaces_CSharp.Contains($CsNamespace)) {$Class_Namespaces_CSharp += $CsNamespace}

            [string]$CsProperty = ""

            ($Content_Lines | Select-String "hidden" -SimpleMatch).LineNumber | ForEach-Object {
                if (([string[]]($Content_Lines[($_ - 1)..($Content_Lines.Count)] | Select-String "\$"))[0].Contains("$" + $property.Name)) {
                    $CsProperty += "    private "
                }
            }
            if (!$CsProperty) {$CsProperty += "    public "}
            if ($property.GetMethod.IsStatic -or $property.SetMethod.IsStatic) {
            
                $CsProperty += "static "

                $Class_Static_Handler_Properties += @{$property.Name = $property.PropertyType}
            }
            else {$Class_Handler_Properties += @{$property.Name = $property.PropertyType}}

            $CsProperty += "$($property.PropertyType) $($property.Name) { get; set; }`n`n"

            $Class_Properties_CSharp += $CsProperty

            
        }

#_ClassHandler------------------------------------------------------------------------------------

        [string]$CsClassHandler = ""

        $CsClassHandler += '
    public object _ClassHandler(string Method, object[] Arguments)
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

        $CsStaticClassHandler += '
    public static object _StaticClassHandler(string Method, object[] Arguments)
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

#Finishing CSharp Class---------------------------------------------------------------------------
		
		[string]$CsClass = ""
		
		$CsClass += $Class_Namespaces_CSharp -join "`n"
		$CsClass += "`n`npublic class $Class_Name`n{`n    "
		$CsClass += "private static PowerShell _Powershell = PowerShell.Create();`n`n    "
		if ($DebugMode) {$CsClass += "public static object GetPowershell() { return _Powershell; }`n`n    "}
        if ($DebugMode) {$CsClass += "public "}
        else {$CsClass += "private "}
		$CsClass += 'static string _Base64Class = "' + [Convert]::ToBase64String([Encoding]::UTF8.GetBytes($Class_Powershell)) + '";' + "`n`n    "
		$CsClass += 'private static void CreatePowershell() 
    {
        string PlainClass = Encoding.UTF8.GetString(Convert.FromBase64String(_Base64Class));
        string ClassHandler = Encoding.UTF8.GetString(Convert.FromBase64String("ZnVuY3Rpb24gQ2xhc3NIYW5kbGVyIChbc3RyaW5nXSRNZXRob2QsIFtvYmplY3RbXV0kQXJndW1lbnRzLCBbaGFzaHRhYmxlXSRQcm9wZXJ0aWVzLCBbYm9vbF0kSXNTdGF0aWMpIHsNCiAgICANCiAgICBmdW5jdGlvbiBSZXR1cm5IYW5kbGVyIChbb2JqZWN0XSRSZXR1cm5WYWx1ZSwgW3N0cmluZ1tdXSRFeGlzdGluZ1Byb3BlcnRpZXMsIFtzd2l0Y2hdJElzU3RhdGljKSB7DQoNCiAgICAgICAgJHRhYmxlICs9IEB7UkVUVVJOID0gJFJldHVyblZhbHVlfQ0KDQogICAgICAgIGlmICgkSXNTdGF0aWMpIHsNCiAgICAgICAgICAgIGZvcmVhY2ggKCRwcm9wZXJ0eSBpbiAkRXhpc3RpbmdQcm9wZXJ0aWVzKSB7DQogICAgICAgICAgICAgICAgJHRhYmxlICs9IEB7JHByb3BlcnR5ID0gJENsYXNzOjokcHJvcGVydHl9DQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgZWxzZSB7DQogICAgICAgICAgICBmb3JlYWNoICgkcHJvcGVydHkgaW4gJEV4aXN0aW5nUHJvcGVydGllcykgew0KICAgICAgICAgICAgICAgICR0YWJsZSArPSBAeyRwcm9wZXJ0eSA9ICRHbG9iYWw6Q2xhc3NfQ29uc3RydWN0ZWQuJHByb3BlcnR5fQ0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgICAgIHJldHVybiAkdGFibGUNCiAgICB9DQoNCiAgICBpZiAoJElzU3RhdGljKSB7DQogICAgICAgIA0KICAgICAgICBpZiAoJFByb3BlcnRpZXMuR2V0RW51bWVyYXRvcigpLk1vdmVOZXh0KCkpIHsNCiAgICAgICAgICAgIGZvcmVhY2ggKCRwcm9wZXJ0eSBpbiAkUHJvcGVydGllcykgew0KICAgICAgICAgICAgICAgICRHbG9iYWw6Q2xhc3M6OigkcHJvcGVydHkuS2V5cykgPSAkcHJvcGVydHkuVmFsdWVzDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgaWYgKCRBcmd1bWVudHMgLWFuZCAkTWV0aG9kKSB7DQogICAgICAgICAgICAkcmV0dXJudmFsdWUgPSAkR2xvYmFsOkNsYXNzOjokTWV0aG9kLkludm9rZSgkQXJndW1lbnRzKQ0KICAgICAgICB9DQogICAgICAgIGVsc2VpZiAoJE1ldGhvZCkgew0KICAgICAgICAgICAgJHJldHVybnZhbHVlID0gJEdsb2JhbDpDbGFzczo6JE1ldGhvZCgpDQogICAgICAgIH0NCiAgICAgICAgUmV0dXJuSGFuZGxlciAtUmV0dXJuVmFsdWUgJHJldHVybnZhbHVlIC1FeGlzdGluZ1Byb3BlcnRpZXMgJFByb3BlcnRpZXMuS2V5cyAtSXNTdGF0aWMNCiAgICB9DQogICAgZWxzZWlmICgkTWV0aG9kIC1lcSAkR2xvYmFsOkNsYXNzLk5hbWUpIHsNCiAgICAgICAgaWYgKCRBcmd1bWVudHMpIHsNCiAgICAgICAgICAgICRHbG9iYWw6Q2xhc3NfQ29uc3RydWN0ZWQgPSBOZXctT2JqZWN0ICRHbG9iYWw6Q2xhc3MuTmFtZSAkQXJndW1lbnRzDQogICAgICAgIH0NCiAgICAgICAgZWxzZSB7DQogICAgICAgICAgICAkR2xvYmFsOkNsYXNzX0NvbnN0cnVjdGVkID0gTmV3LU9iamVjdCAkR2xvYmFsOkNsYXNzLk5hbWUNCiAgICAgICAgfQ0KICAgICAgICBSZXR1cm5IYW5kbGVyIC1SZXR1cm5WYWx1ZSAiTlVMTCIgLUV4aXN0aW5nUHJvcGVydGllcyAkUHJvcGVydGllcy5LZXlzDQogICAgfQ0KICAgIGVsc2Ugew0KICAgICAgICBpZiAoJFByb3BlcnRpZXMuR2V0RW51bWVyYXRvcigpLk1vdmVOZXh0KCkpIHsNCiAgICAgICAgICAgIGZvcmVhY2ggKCRwcm9wZXJ0eSBpbiAkUHJvcGVydGllcykgew0KICAgICAgICAgICAgICAgICRHbG9iYWw6Q2xhc3NfQ29uc3RydWN0ZWQuKCRwcm9wZXJ0eS5LZXlzKSA9ICRwcm9wZXJ0eS5WYWx1ZXMNCiAgICAgICAgICAgIH0gIA0KICAgICAgICB9ICAgIA0KICAgICAgICBpZiAoJEFyZ3VtZW50cyAtYW5kICRNZXRob2QpIHsNCiAgICAgICAgICAgICRyZXR1cm52YWx1ZSA9ICRHbG9iYWw6Q2xhc3NfQ29uc3RydWN0ZWQuJE1ldGhvZC5JbnZva2UoJEFyZ3VtZW50cykNCiAgICAgICAgfQ0KICAgICAgICBlbHNlaWYgKCRNZXRob2QpIHsNCiAgICAgICAgICAgICRyZXR1cm52YWx1ZSA9ICRHbG9iYWw6Q2xhc3NfQ29uc3RydWN0ZWQuJE1ldGhvZCgpDQogICAgICAgIH0NCiAgICAgICAgUmV0dXJuSGFuZGxlciAtUmV0dXJuVmFsdWUgJHJldHVybnZhbHVlIC1FeGlzdGluZ1Byb3BlcnRpZXMgJFByb3BlcnRpZXMuS2V5cw0KICAgIH0NCn0="));

        _Powershell.AddScript(PlainClass);
        _Powershell.AddScript(ClassHandler);
        _Powershell.Invoke();
    }' + "`n`n"
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

    Write-Output "`nSucesss, exitet with code:"

    return 0
}
