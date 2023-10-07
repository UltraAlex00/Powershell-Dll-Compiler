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

.PARAMETER SkipUpdate
Doesn't check for updates.

.EXAMPLE
Compile-Dll .\example.psm1 -o .\example.dll

.EXAMPLE
Compile-Dll .\example.psm1 -o .\example.cs

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
        
        [Parameter(Position = 0)]
        [string]$Path,

        [Parameter(ValueFromPipeline)]
        [string]$ScriptDefinition,

        [string[]]$ModuleReferences,

        [Alias("o")]
        [Parameter(Position = 1)]
        [string]$OutputAssembly,

        [switch]$DebugMode,

        [switch]$SkipUpdate
    )

    $ErrorActionPreference = [ActionPreference]::Stop

    #Update Check

    if (!$SkipUpdate) {

        Write-Host "`nChecking for Updates...`n"

        if ([Updater]::UpdateAvailable()) {
        
            Write-Host "New update found!, use 'Update-Module PSDllCompiler'

Current version: $([Updater]::CurrentVersion)
Newest version:  $([Updater]::NewestVersion)

Release Notes:
$([Updater]::GetReleaseNotes()) 
"
            pause
        }
    }

    

    if ($Path) {$Content = Get-Content $Path -Raw}
    elseif ($ScriptDefinition) {$Content = $ScriptDefinition}
    else {throw "Provide a input code using -Path or -ScriptDefinition !"}

    if (!$OutputAssembly) {throw "Provide a output path location using -OutputAssembly !"}
    if (($OutputAssembly.Split(".") | Select-Object -Last 1) -notin @("dll", "cs")) {throw "Invalid file format! Valid formats: *.dll, *.cs"}
    if (Test-Path $OutputAssembly) {throw "File '$OutputAssembly' allready exists!"}

    #adding class
    Invoke-Expression $Content

    #adding include refs
    [string[]]$ModuleReferences += $Content.Split("`n") | Select-String "#include " -SimpleMatch | ForEach-Object {([string]$_).Replace("#include ", "").Split(",")} | ForEach-Object {$_.Trim()}

    #removing comments (& refs)
    $Content = $Content -split "<#"
    [string]$Content_Clean = ""
    for ($i = 0; $i -lt $Content.Count; $i++) {
        if ($i % 2 -eq 0) {$Content_Clean += $Content[$i]}
        else {$Content_Clean += ($Content[$i] -split "#>")[1].Trim()}
    }
    [string[]]$Content_Lines = $Content_Clean.Split("`n") | ForEach-Object {([string]$_).Split("#")[0]}
    [string]$Content = $Content_Lines -join "`n"

    if ($Content -match "Write-Output") {throw "at $(($Content_Lines | Select-String "Write-Output" -SimpleMatch).LineNumber): Class cannot contain Write-Output !"}

    [string[]]$ClassNames = $Content_Lines | Select-String "class" | Where-Object {!([string]$_).Contains("(") -and !([string]$_).Contains("$")} | ForEach-Object {([string]$_).Split(" ")[1]}

    [string]$Class_Csharp = ""

    for ([int]$progress = 0; $progress -lt $ClassNames.Count; $progress++) {
        
        $Class_Name = $ClassNames[$progress]

        Write-Host "Compiling $Class_Name [$([string]($progress + 1) + "/" + $ClassNames.Count)]..."

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
        [string]$Class_Powershell_Basecode = $Content_Lines[(($Content_Lines | Select-String "class $($ClassNames[$progress]) ").LineNumber - 1)..($Content_Lines.Count - (($Content_Lines | Select-String "class $($ClassNames[$progress + 1]) ").LineNumber - 2))] -join "`n"


#Function References------------------------------------------------------------------------------
        
        $References_Powershell += '[string[]]$References_Module_b64 = @()' + "`n"

        if ($PSVersionTable.PSVersion -ge [Version]"6.0") {$InstalledModules = Get-Command -Module ((Get-ChildItem "C:\Program Files\WindowsPowerShell\Modules").Name | Where-Object {$_ -notin @("PackageManagement", "PowerShellGet")})} #Powershell Core and it sux balls
        else {$InstalledModules = Get-Command -Module (Get-InstalledModule | Where-Object {$_.Name -notin @("PackageManagement", "PowerShellGet")}).Name} #Windows Powershell

        foreach ($command in $InstalledModules) {

            if ($Class_Powershell_Basecode -match $command.Name) {
                if ($command.ModuleName -cin $ModuleReferences) {
                    
                    Write-Host "    Adding $($command.ModuleName)..."

                    $module = Get-Item $command.Module.Path

                    $tmpfile = Join-Path $env:TMP ((New-Guid).Guid + ".zip")
                    Compress-Archive "$($module.DirectoryName)\*" $tmpfile -CompressionLevel Optimal -Force
                    $b64module = [Convert]::ToBase64String([File]::ReadAllBytes($tmpfile))
                    Remove-Item $tmpfile

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
    Remove-Item $tmpfile
    (Get-Childitem "$tmpfolder\*.psd1").FullName | Foreach-Object {Import-Module ([string]$_)}
}'

#Powershell Class---------------------------------------------------------------------------------

        $Class_Powershell += (($Content_Lines | Select-String @("using namespace", "using module", "using assembly") -SimpleMatch) -join "`n") + "`n"
        $Class_Powershell += $Class_Powershell_Basecode
        $Class_Powershell += "`n`n" + '$Global:Class = [' + "$Class_Name]`n"
        $Class_Powershell += '$Global:Class_Constructed = $null' + "`n`n"

#Class Constructors-------------------------------------------------------------------------------
        
        foreach ($constructor in $Class_Constructors) {

            $Class_Constructors_CSharp += "    public $Class_Name ("
            $Class_Constructors_CSharp += "$([string]($constructor.GetParameters() -join ", ")))`n    {`n        "
            $Class_Constructors_CSharp += "object[] Arguments = { $([string]($constructor.GetParameters().Name -join ", ")) };`n`n        "
            $Class_Constructors_CSharp += "_ClassHandler($('"' + $Class_Name + '"'), Arguments);"
            $Class_Constructors_CSharp += "`n    }`n`n"
        }

#Class Methods------------------------------------------------------------------------------------

        foreach ($method in $Class_Methods) {
            
            [string]$CsNamespace = ""
            
            $CsNamespace = "using $($method.ReturnType.Namespace);"
            if (!$Class_Namespaces_CSharp.Contains($CsNamespace)) {$Class_Namespaces_CSharp += $CsNamespace}

            $Class_Methods_CSharp += "    "

            switch ($method) {
    
                {$_.IsPublic} {$Class_Methods_CSharp += "public "}
                {$_.IsPrivate} {$Class_Methods_CSharp += "private "}
                {$_.IsStatic} {$Class_Methods_CSharp += "static "}
            }
            $Class_Methods_CSharp += "$($method.ReturnType.Name) "
            $Class_Methods_CSharp += "$($method.Name) ("
            $Class_Methods_CSharp += "$([string]($method.GetParameters() -join ", ")))`n    {`n        "
            $Class_Methods_CSharp += "object[] Arguments = { $([string]($method.GetParameters().Name -join ", ")) };`n`n        "
            if ($method.IsStatic) {
                if ($method.ReturnType.Name -eq "void") {$Class_Methods_CSharp += "_StaticClassHandler($('"' + $method.Name + '"'), Arguments);"}
                else {$Class_Methods_CSharp += "return ($($method.ReturnType.Name))_StaticClassHandler($('"' + $method.Name + '"'), Arguments);"}
            }
            else {
                if ($method.ReturnType.Name -eq "void") {$Class_Methods_CSharp += "_ClassHandler($('"' + $method.Name + '"'), Arguments);"}
                else {$Class_Methods_CSharp+= "return ($($method.ReturnType.Name))_ClassHandler($('"' + $method.Name + '"'), Arguments);"}
            }
            $Class_Methods_CSharp += "`n    }`n`n"
            $Class_Methods_CSharp = $Class_Methods_CSharp.Replace("Void", "void")
        }

#Class Properties---------------------------------------------------------------------------------

        foreach ($property in $Class_Properties) {

            $CsNamespace = "using $($property.PropertyType.Namespace);"
            if (!$Class_Namespaces_CSharp.Contains($CsNamespace)) {$Class_Namespaces_CSharp += $CsNamespace}

            [string]$CsProperty = ""

            ($Class_Powershell_Basecode.Split("`n") | Select-String "hidden" -SimpleMatch).LineNumber | ForEach-Object {
                if ($_ -and ([string](($Content_Lines[($_ - 1)..$Content_Lines.Count] | Select-String "\$")[0]) -match ("$" + $property.Name))) {
                    $Class_Properties_CSharp += "    private "
                }
                else {$Class_Properties_CSharp += "    public "}
            }
            if ($property.GetMethod.IsStatic -or $property.SetMethod.IsStatic) {
            
                $Class_Properties_CSharp += "static "

                $Class_Static_Handler_Properties += @{$property.Name = $property.PropertyType.Name}
            }
            else {$Class_Handler_Properties += @{$property.Name = $property.PropertyType.Name}}

            $Class_Properties_CSharp += "$($property.PropertyType.Name) $($property.Name) { get; set; }`n`n"
        }

#_ClassHandler------------------------------------------------------------------------------------

        if ($DebugMode) {$Class_Handler_CSharp += "`n    public "}
        else {$Class_Handler_CSharp += "`n    private "}

        $Class_Handler_CSharp += 'object _ClassHandler(string Method, object[] Arguments)
    {
        if (_Powershell.Commands.Commands.Count == 0) { CreatePowershell(); }

        string Script = Encoding.UTF8.GetString(Convert.FromBase64String("cGFyYW0gKFtzdHJpbmddJE1ldGhvZCwgW29iamVjdFtdXSRBcmd1bWVudHMsIFtoYXNodGFibGVdJFByb3BlcnRpZXMpDQpDbGFzc0hhbmRsZXIgJE1ldGhvZCAkQXJndW1lbnRzICRQcm9wZXJ0aWVzICRmYWxzZQ=="));

        Hashtable Properties = new Hashtable();'
        foreach ($property in $Class_Handler_Properties) {
        
            $Class_Handler_CSharp += "`n        Properties.Add($('"' + $property.Keys + '"'), $($property.Keys));`n"
        }
        $Class_Handler_CSharp += '
        _Powershell.Commands.Commands.Clear();
        _Powershell.AddScript(Script);
        _Powershell.AddArgument(Method);
        _Powershell.AddArgument(Arguments);
        _Powershell.AddArgument(Properties);

        Hashtable returnproperties = _Powershell.Invoke()[0].BaseObject as Hashtable;
    '
        foreach ($property in $Class_Handler_Properties) {
        
            $Class_Handler_CSharp += "`n        $($property.Keys) = ($($property.Values))returnproperties[$('"' + $property.Keys + '"')];"
        }
        $Class_Handler_CSharp += '
        
        foreach (InformationRecord message in _Powershell.Streams.Information)
        {
            Console.WriteLine(message);
        }
        foreach (WarningRecord message in _Powershell.Streams.Warning)
        {
            Console.WriteLine("WARNING: {0}", message);
        }
        _Powershell.Streams.ClearStreams();

        '
        $Class_Handler_CSharp += "return returnproperties" + '["RETURN"];' + "`n    }`n`n"

#_StaticClassHandler------------------------------------------------------------------------------

        if ($DebugMode) {$Class_Static_Handler_CSharp += "`n    public "}
        else {$Class_Static_Handler_CSharp += "`n    private "}

        $Class_Static_Handler_CSharp += 'static object _StaticClassHandler(string Method, object[] Arguments)
    {
        if (_Powershell.Commands.Commands.Count == 0) { CreatePowershell(); }

        string Script = Encoding.UTF8.GetString(Convert.FromBase64String("cGFyYW0gKFtzdHJpbmddJE1ldGhvZCwgW29iamVjdFtdXSRBcmd1bWVudHMsIFtoYXNodGFibGVdJFByb3BlcnRpZXMpDQpDbGFzc0hhbmRsZXIgJE1ldGhvZCAkQXJndW1lbnRzICRQcm9wZXJ0aWVzICR0cnVl"));

        Hashtable Properties = new Hashtable();'
        foreach ($property in $Class_Static_Handler_Properties) {
        
            $Class_Static_Handler_CSharp += "`n        Properties.Add($('"' + $property.Keys + '"'), $($property.Keys));`n"
        }
        $Class_Static_Handler_CSharp += '
        _Powershell.Commands.Commands.Clear();
        _Powershell.AddScript(Script);
        _Powershell.AddArgument(Method);
        _Powershell.AddArgument(Arguments);
        _Powershell.AddArgument(Properties);

        Hashtable returnproperties = _Powershell.Invoke()[0].BaseObject as Hashtable;
    '
        foreach ($property in $Class_Static_Handler_Properties) {
        
            $Class_Static_Handler_CSharp += "`n        $($property.Keys) = ($($property.Values))returnproperties[$('"' + $property.Keys + '"')];"
        }
        $Class_Static_Handler_CSharp += '
        
        foreach (InformationRecord message in _Powershell.Streams.Information)
        {
            Console.WriteLine(message);
        }
        foreach (WarningRecord message in _Powershell.Streams.Warning)
        {
            Console.WriteLine("WARNING: {0}", message);
        }
        _Powershell.Streams.ClearStreams();

        '
        $Class_Static_Handler_CSharp += "return returnproperties" + '["RETURN"];' + "`n    }`n"

#CreatePowershell---------------------------------------------------------------------------------
        
        if ($DebugMode) {$Class_CreatePowershell_CSharp += "public "}
        else {$Class_CreatePowershell_CSharp += "private "}

        $Class_CreatePowershell_CSharp += 'static void CreatePowershell() 
    {
        string PlainRef = Encoding.UTF8.GetString(Convert.FromBase64String(_Base64Ref));
        string PlainClass = Encoding.UTF8.GetString(Convert.FromBase64String(_Base64Class));
        string ClassHandler = Encoding.UTF8.GetString(Convert.FromBase64String("JEdsb2JhbDpGaXJzdFJ1biA9ICR0cnVlDQokR2xvYmFsOkZpcnN0UnVuX1N0YXRpYyA9ICR0cnVlDQpmdW5jdGlvbiBDbGFzc0hhbmRsZXIgKFtzdHJpbmddJE1ldGhvZCwgW29iamVjdFtdXSRBcmd1bWVudHMsIFtoYXNodGFibGVdJFByb3BlcnRpZXMsIFtib29sXSRJc1N0YXRpYykgew0KICAgIA0KICAgIGZ1bmN0aW9uIFJldHVybkhhbmRsZXIgKFtvYmplY3RdJFJldHVyblZhbHVlLCBbc3RyaW5nW11dJEV4aXN0aW5nUHJvcGVydGllcywgW3N3aXRjaF0kSXNTdGF0aWMpIHsNCg0KICAgICAgICAkdGFibGUgKz0gQHtSRVRVUk4gPSAkUmV0dXJuVmFsdWV9DQoNCiAgICAgICAgaWYgKCRJc1N0YXRpYykgew0KICAgICAgICAgICAgZm9yZWFjaCAoJHByb3BlcnR5IGluICRFeGlzdGluZ1Byb3BlcnRpZXMpIHsNCiAgICAgICAgICAgICAgICAkdGFibGUgKz0gQHskcHJvcGVydHkgPSAkR2xvYmFsOkNsYXNzOjokcHJvcGVydHl9DQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgZWxzZSB7DQogICAgICAgICAgICBmb3JlYWNoICgkcHJvcGVydHkgaW4gJEV4aXN0aW5nUHJvcGVydGllcykgew0KICAgICAgICAgICAgICAgICR0YWJsZSArPSBAeyRwcm9wZXJ0eSA9ICRHbG9iYWw6Q2xhc3NfQ29uc3RydWN0ZWQuJHByb3BlcnR5fQ0KICAgICAgICAgICAgfQ0KICAgICAgICB9DQogICAgICAgIHJldHVybiAkdGFibGUNCiAgICB9DQoNCiAgICBpZiAoJElzU3RhdGljKSB7DQogICAgICAgIA0KICAgICAgICBpZiAoKCRHbG9iYWw6Rmlyc3RSdW5fU3RhdGljIC1hbmQgIVtzdHJpbmddOjpJc051bGxPckVtcHR5KCRQcm9wZXJ0aWVzLlZhbHVlcykpIC1vciAhJEdsb2JhbDpGaXJzdFJ1bl9TdGF0aWMpIHsNCiAgICAgICAgICAgIGZvcmVhY2ggKCRwcm9wZXJ0eSBpbiAkUHJvcGVydGllcy5LZXlzKSB7DQogICAgICAgICAgICAgICAgJEdsb2JhbDpDbGFzczo6KCRwcm9wZXJ0eSkgPSAkUHJvcGVydGllc1skcHJvcGVydHldDQogICAgICAgICAgICB9DQogICAgICAgIH0NCiAgICAgICAgJEdsb2JhbDpGaXJzdFJ1bl9TdGF0aWMgPSAkZmFsc2UNCg0KICAgICAgICAkcmV0dXJudmFsdWUgPSAkR2xvYmFsOkNsYXNzOjokTWV0aG9kLkludm9rZSgkQXJndW1lbnRzKQ0KICAgICAgICBSZXR1cm5IYW5kbGVyICRyZXR1cm52YWx1ZSAkUHJvcGVydGllcy5LZXlzIC1Jc1N0YXRpYw0KICAgIH0NCiAgICBlbHNlaWYgKCRNZXRob2QgLWVxICRHbG9iYWw6Q2xhc3MuTmFtZSkgew0KDQogICAgICAgICRHbG9iYWw6Q2xhc3NfQ29uc3RydWN0ZWQgPSBOZXctT2JqZWN0ICRHbG9iYWw6Q2xhc3MuTmFtZSAkQXJndW1lbnRzDQoNCiAgICAgICAgUmV0dXJuSGFuZGxlciAiTlVMTCIgJFByb3BlcnRpZXMuS2V5cw0KICAgIH0NCiAgICBlbHNlIHsNCiAgICAgICAgaWYgKCgkR2xvYmFsOkZpcnN0UnVuIC1hbmQgIVtzdHJpbmddOjpJc051bGxPckVtcHR5KCRQcm9wZXJ0aWVzLlZhbHVlcykpIC1vciAhJEdsb2JhbDpGaXJzdFJ1bikgew0KICAgICAgICAgICAgZm9yZWFjaCAoJHByb3BlcnR5IGluICRQcm9wZXJ0aWVzLktleXMpIHsNCiAgICAgICAgICAgICAgICAkR2xvYmFsOkNsYXNzX0NvbnN0cnVjdGVkLigkcHJvcGVydHkpID0gJFByb3BlcnRpZXNbJHByb3BlcnR5XQ0KICAgICAgICAgICAgfSAgDQogICAgICAgIH0NCiAgICAgICAgJEdsb2JhbDpGaXJzdFJ1biA9ICRmYWxzZSAgIA0KICAgICAgICANCiAgICAgICAgJHJldHVybnZhbHVlID0gJEdsb2JhbDpDbGFzc19Db25zdHJ1Y3RlZC4kTWV0aG9kLkludm9rZSgkQXJndW1lbnRzKQ0KICAgICAgICBSZXR1cm5IYW5kbGVyICRyZXR1cm52YWx1ZSAkUHJvcGVydGllcy5LZXlzDQogICAgfQ0KfQ=="));

        _Powershell.AddScript(PlainRef);
        _Powershell.AddScript(PlainClass);
        _Powershell.AddScript(ClassHandler);
        _Powershell.Invoke();
    }' + "`n`n"

#Finishing CSharp Class---------------------------------------------------------------------------
		
		$Class_Csharp += "`n`npublic class $Class_Name`n{`n    "
		$Class_Csharp += "private static PowerShell _Powershell = PowerShell.Create();`n`n    "
		if ($DebugMode) {$Class_Csharp += "public static object GetPowershell() { return _Powershell; }`n`n    "}
        if ($DebugMode) {$Class_Csharp += "public "}
        else {$Class_Csharp += "private "}
		$Class_Csharp += 'static string _Base64Class = "' + [Convert]::ToBase64String([Encoding]::UTF8.GetBytes($Class_Powershell)) + '";' + "`n`n    "
        if ($DebugMode) {$Class_Csharp += "public "}
        else {$Class_Csharp += "private "}
        $Class_Csharp += 'static string _Base64Ref = "' + [Convert]::ToBase64String([Encoding]::UTF8.GetBytes($References_Powershell)) + '";' + "`n`n    "
        $Class_Csharp += $Class_CreatePowershell_CSharp

		$Class_Csharp += $Class_Static_Handler_CSharp
		$Class_Csharp += $Class_Handler_CSharp
        
        $Class_Csharp += "    //Visible Class`n`n"

        $Class_Csharp += $Class_Constructors_CSharp
		$Class_Csharp += $Class_Properties_CSharp
		$Class_Csharp += $Class_Methods_CSharp
		$Class_Csharp += "}"
    }

    $Class_Csharp = ($Class_Namespaces_CSharp -join "`n") + $Class_Csharp

#Writing Class_CSharp-----------------------------------------------------------------------------
    
    if ($OutputAssembly.Contains(".dll")) {
    
        Add-Type -TypeDefinition $Class_Csharp -OutputAssembly $OutputAssembly | Out-Null
    }
    elseif ($OutputAssembly.Contains(".cs")) {
        
        New-Item -Path $OutputAssembly -Value $Class_Csharp | Out-Null
    }

    Write-Host "`nSucesss, $((Get-Item $OutputAssembly).Name) has been compiled!"
}
