# Powershell Dll Compiler
Translates a `Powershell Class` into a `C# Class` and then compiles it. This class can be referenced across all .NET Languages.
Project is currently in `alpha` state, so there will be some bugs. Please Report them!!

Powershell Gallery: (https://www.powershellgallery.com/packages/PSDllCompiler/1.0.0)
Discord: ultraalex0

# Installation
This Project can be found on the Powershell Gallery () and can be installed with the command:
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
In **.NET Projects** by simply adding the dll to the references and importing it:
```CSharp
//C#

using static ExampleClass;
```
# Limitations - v1.0.0-alpha - 23.8.2023
### Will be fixed
* class cannot contain a reference to other dll
* class default path is %USERPROFILE%, not the dll Path
* hidden members cannot be called
* multiple classes
* partial classes
### Will not be fixed
