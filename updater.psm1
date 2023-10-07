class Updater {

    static [Version]$CurrentVersion = (Import-PowerShellDataFile "$([Environment]::CurrentDirectory)\PSDllCompiler.psd1").ModuleVersion

    static [Version]$NewestVersion = (Find-Module PSDllCompiler).Version

    static [bool] UpdateAvailable() {
    
        if ([Updater]::NewestVersion -gt [Updater]::CurrentVersion) {return $true}

        return $false
    }
    static [string] GetReleaseNotes() {
        
        $response = Invoke-RestMethod -Uri "https://www.powershellgallery.com/packages/PSDllCompiler"

        $index = ($response.Split("`n") | Select-String @("Release Notes", "FileList ")).LineNumber

        $ReleaseNotes = [string]($response.Split("`n")[$index[0]..($index[1] - 3)]).Replace("<br />", "`n")
        $ReleaseNotes = $ReleaseNotes.Replace('<p class="content-collapse-in">', "").Replace("</p>", "").Replace("</div>", "").Trim()

        return $ReleaseNotes
    }
}
