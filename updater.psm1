class Updater {

    static [Version]$Version = (Import-PowerShellDataFile .\PSDllCompiler.psd1).ModuleVersion

    static [bool] UpdateAvailable() {
    
        if ((Find-Module PSDllCompiler).Version -gt [Updater]::Version) {return $true}

        return $false
    }
}