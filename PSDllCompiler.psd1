#
# Module manifest for module 'Powershell Dll Compiler'
#
# Generated by: Alex
#
# Generated on: 2023-8-23
#

@{

# Script module or binary module file associated with this manifest.
RootModule = 'PSDllCompiler.psm1'

# Version number of this module.
ModuleVersion = '1.0.1'

# Supported PSEditions
# CompatiblePSEditions = @()

# ID used to uniquely identify this module
GUID = '119E1238-C602-476E-BE59-5F7EFAD3CC37'

# Author of this module
Author = 'UltraAlex0'

# Company or vendor of this module
CompanyName = ''

# Copyright statement for this module
Copyright = '(c) Alex 2023'

# Description of the functionality provided by this module
Description = @'
Translates a Powershell Class into a C# Class and then compiles it. The class can be referenced across all .NET Languages.
Additionally all Installed-Modules can be referenced and used!

Discord: ultraalex0
'@

# Minimum version of the Windows PowerShell engine required by this module
PowerShellVersion = '3.0'

# Name of the Windows PowerShell host required by this module
# PowerShellHostName = ''

# Minimum version of the Windows PowerShell host required by this module
# PowerShellHostVersion = ''

# Minimum version of Microsoft .NET Framework required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
DotNetFrameworkVersion = '4.0'

# Minimum version of the common language runtime (CLR) required by this module. This prerequisite is valid for the PowerShell Desktop edition only.
# CLRVersion = ''

# Processor architecture (None, X86, Amd64) required by this module
# ProcessorArchitecture = ''

# Modules that must be imported into the global environment prior to importing this module
# RequiredModules = @()

# Assemblies that must be loaded prior to importing this module
# RequiredAssemblies = @()

# Script files (.ps1) that are run in the caller's environment prior to importing this module.
# ScriptsToProcess = @()

# Type files (.ps1xml) to be loaded when importing this module
# TypesToProcess = @()

# Format files (.ps1xml) to be loaded when importing this module
# FormatsToProcess = @()

# Modules to import as nested modules of the module specified in RootModule/ModuleToProcess
# NestedModules = @()

# Functions to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no functions to export.
FunctionsToExport = @('Compile-Dll')

# Cmdlets to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no cmdlets to export.
CmdletsToExport = @()

# Variables to export from this module
VariablesToExport = @()

# Aliases to export from this module, for best performance, do not use wildcards and do not delete the entry, use an empty array if there are no aliases to export.
AliasesToExport = @()

# DSC resources to export from this module
# DscResourcesToExport = @()

# List of all modules packaged with this module
# ModuleList = @()

# List of all files packaged with this module
# FileList = @()

# Private data to pass to the module specified in RootModule/ModuleToProcess. This may also contain a PSData hashtable with additional module metadata used by PowerShell.
PrivateData = @{

	PSData = @{
		# Tags applied to this module. These help with module discovery in online galleries.
		Tags = @('Powershell', 'Dll', 'Class', 'Compiler', 'CSharp', 'ps2dll')

		# A URL to the license for this module.
		LicenseUri = 'https://github.com/UltraAlex00/Powershell-Dll-Compiler/blob/main/LICENSE'

		# A URL to the main website for this project.
		ProjectUri = 'https://github.com/UltraAlex00/Powershell-Dll-Compiler'

		# A URL to an icon representing this module.
		# IconUri = ''

		# ReleaseNotes of this module
		ReleaseNotes = @'
1.0.1-beta 31.8.2023
* Added Module Reference system
* Fixed Constructors beeing written 2x
* Fixed Properties beeing recognized as private incorrectly
* Fixed Types not beeing recognized due to lowercase
* Fixed crash on updates

Next Update
* .NET 6.0 Support
* Read-Host
* Write-Host etc.

High Priority
* multiple classes
* partial classes

Low Priority
* hidden members are not acessable externaly
* enum classes
'@
	} # End of PSData hashtable

} # End of PrivateData hashtable

# HelpInfo URI of this module
# HelpInfoURI = ''

# Default prefix for commands exported from this module. Override the default prefix using Import-Module -Prefix.
# DefaultCommandPrefix = ''

}
