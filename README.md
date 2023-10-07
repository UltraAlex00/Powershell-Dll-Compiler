# Powershell Dll Compiler
Translates a `Powershell Class` into a `C# Class` and then compiles it. This class can be referenced across all .NET Languages.
Project is currently in **alpha** state, so there will be some bugs. Please Report them!!

Discord: ultraalex0

# Installation
This Project can be found on the [Powershell Gallery](https://www.powershellgallery.com/packages/PSDllCompiler) and can be installed with the command:
```powershell
Install-Module PSDllCompiler
```

# Usage
Lets say you have a Class in example.ps1:
```powershell
using namespace System.Windows.Forms #namespaces can be used if needed

class ExampleClass {

  [string]$Name

  [string] GreetMe() {

    return "Hello $($this.Name)"
  }

  [int] Add([int]$Num1, [int]$Num2) {

    return $Num1 + $Num2
  }
}
```
Now compile it with:
```powershell
Compile-Dll -Path .\example.ps1 -OutputAssembly .\example.dll
```
Your dll can now be imported in other **powershell projecs** using:
```powershell
using assembly example.dll #option 1
Add-Type -Path example.dll #option 2
[Reflection.Assembly]::LoadFile("example.dll") #option 3
```
In **.NET Projects** by simply adding the dll to the references, installing the NuGet package "`Microsoft.PowerShell.SDK`" and importing it using:
```CSharp
//C#

using static ExampleClass;
```
# Module References
You can use functions from other modules by referencing them
```Powershell
#include PSDllCompiler  <---------

class CompilerTest {

  static [void] Compile([string]$input, [string]$output) {

    Compile-Dll -Path $input -OutputAssembly $output
  }  
}
```
or using the argument `-ModuleReferences @("PSDllCompiler")`

# v1.0.2-beta - 7.10.2023
* Added support for multiple classes
* Added support for Write-Host, Write-Warning
* Added argument -SkipUpdate
* Fixed method-property sync (temporary fix)
* Improved ClassHandler_Powershell
### Next Update
* independent property sync
### High Priority
* partial classes
### Low Priority
* Read-Host
* class namespaces
