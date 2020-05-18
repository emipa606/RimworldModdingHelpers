# First get the settings from the json-file
$settingsFilePath = "$PSScriptRoot\settings.json"
if(-not (Test-Path $settingsFilePath)) {
	Write-Host "Could not find settingsfile: $settingsFilePath, exiting."
	return
}
$Global:settings = Get-Content -Path $settingsFilePath -raw | ConvertFrom-Json
$Global:localModFolder = "$($settings.rimworld_folder_path)\Mods"
$Global:playingModsConfig = "$PSScriptRoot\ModsConfig_Playing.xml"
$Global:moddingModsConfig = "$PSScriptRoot\ModsConfig_Modding.xml"
$Global:replacementsFile = "$PSScriptRoot\ReplaceRules.txt"
$Global:manifestTemplate = "$PSScriptRoot\$($settings.manfest_template)"
if(-not (Test-Path $manifestTemplate)) {
	Write-Host "Manifest-template not found: $manifestTemplate, exiting."
	return
}
$Global:gitignoreTemplate = "$PSScriptRoot\$($settings.gitignore_template)"
if(-not (Test-Path $gitignoreTemplate)) {
	Write-Host "gitignore-template not found: $gitignoreTemplate, exiting."
	return
}
$Global:publisherPlusTemplate = "$PSScriptRoot\$($settings.publisher_plus_template)"
$Global:modSyncTemplate = "$PSScriptRoot\$($settings.modsync_template)"
$Global:licenseFile = "$PSScriptRoot\$($settings.license_file)"

# Helper-function
# Select folder dialog, for selecting mod-folder manually
Function Get-Folder($initialDirectory) {
    [System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms")|Out-Null
    $folder = $false
    $foldername = New-Object System.Windows.Forms.FolderBrowserDialog
    $foldername.Description = "Select a folder"
    $foldername.rootfolder = "MyComputer"
    $foldername.SelectedPath = $localModFolder
    $foldername.ShowNewFolderButton = $false

    if($foldername.ShowDialog() -eq "OK")
    {
        $folder = $foldername.SelectedPath
    }
    return $folder
}

# Helper-function
# Checks if a github-repository already exists
Function Get-RepositoryStatus {
    param ($repositoryName)
    # First we create the request.
    $HTTP_Request = [System.Net.WebRequest]::Create("https://github.com/$($settings.github_username)/$repositoryName")

    # We then get a response from the site.
    $HTTP_Response = $HTTP_Request.GetResponse()

    # We then get the HTTP code as an integer.
    $HTTP_Status = [int]$HTTP_Response.StatusCode

    If ($HTTP_Response -ne $null) { $HTTP_Response.Close() }

    If ($HTTP_Status -eq 200) {
        return $true
    }
    return $false
}

# Helper-function
# Generates a new ModSync-file for a mod
function New-ModSyncFile {
  param (
    $targetPath,
    $modWebPath,
    $modname,
    $version
  )
  if(-not (Test-Path $settings.modsync_template)) {
	  Write-Host "Cound not find ModSync-template: $($settings.modsync_template), skipping."
	  return
  }
  Copy-Item $settings.modsync_template $targetPath -Force
  ((Get-Content -path $targetPath -Raw).Replace("[guid]", [guid]::NewGuid().ToString())) | Set-Content -Path $targetPath
  ((Get-Content -path $targetPath -Raw).Replace("[modname]", $modname)) | Set-Content -Path $targetPath
  ((Get-Content -path $targetPath -Raw).Replace("[version]", $version)) | Set-Content -Path $targetPath
  ((Get-Content -path $targetPath -Raw).Replace("[username]", $settings.github_username)) | Set-Content -Path $targetPath
  ((Get-Content -path $targetPath -Raw).Replace("[modwebpath]", $modWebPath)) | Set-Content -Path $targetPath  
}

# Texturename function
# Checks for textures with the old naming-style (side/front/back) and replaces it
# with the new style (east/south/north)
function Update-Textures {
	$currentDirectory = (Get-Location).Path
	if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
		Write-Host "Can only be run from somewhere under $localModFolder, exiting"
		return			
	}
	$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	$modFolder = "$localModFolder\$modName"
	Set-Location $modFolder
	$files = Get-ChildItem . -Recurse
	foreach ($file in $files) { 
		if(-not $file.FullName.Contains("Textures")){
			continue
		}
		$newName = $file.Name.Replace("_side", "_east").Replace("_front", "_south").Replace("_back", "_north")
		$newPath = $file.FullName.Replace($file.Name, $newName)
		Move-Item $file.FullName "$newPath" -ErrorAction SilentlyContinue | Out-Null
	}
}

# Easy load of a mods steam-page
# Gets the published ID for a mod and then opens it in the selected browser
function Get-ModPage {
	$currentDirectory = (Get-Location).Path
	if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
		Write-Host "Can only be run from somewhere under $localModFolder, exiting"
		return			
	}
	$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	$modFileId = "$localModFolder\$modName\About\PublishedFileId.txt"
	$modId = Get-Content $modFileId -Raw
	$applicationPath = $settings.browser_path
	$arguments = "https://steamcommunity.com/sharedfiles/filedetails/?id=$modId"
	Start-Process -FilePath $applicationPath -ArgumentList $arguments	
}

# Start RimWorld two different ways
# Default start is as mod-publish mode
#	- Windowed mode
# 	- Developer mode on
#	- Dont reset modlist on errors
# Using the -play parameter starts in play mode
#	- Fullscreen mode
#	- Developer mode off
# Each mode has its own modlist
function Start-RimWorld {
	[CmdletBinding()]
	param ([switch]$play)

	$prefsFile = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\Prefs.xml"
	$modFile = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\ModsConfig.xml"

	$currentActiveMods = Get-Content $modFile
	if($currentActiveMods.Length -gt 20) {
		$currentActiveMods | Set-Content -Path $playingModsConfig
	} else {
		$currentActiveMods | Set-Content -Path $moddingModsConfig
	}

	if($play) {
		Copy-Item $playingModsConfig $modFile -Confirm:$false
		(Get-Content $prefsFile -Raw).Replace("<devMode>True</devMode>", "<devMode>False</devMode>").Replace("<screenWidth>$($settings.modding_screen_witdh)</screenWidth>", "<screenWidth>$($settings.playing_screen_witdh)</screenWidth>").Replace("<screenHeight>$($settings.modding_screen_height)</screenHeight>", "<screenHeight>$($settings.playing_screen_height)</screenHeight>").Replace("<fullscreen>False</fullscreen>", "<fullscreen>True</fullscreen>") | Set-Content $prefsFile
	} else {
		Copy-Item $moddingModsConfig $modFile -Confirm:$false
		(Get-Content $prefsFile -Raw).Replace("<resetModsConfigOnCrash>True</resetModsConfigOnCrash>", "<resetModsConfigOnCrash>False</resetModsConfigOnCrash>").Replace("<devMode>False</devMode>", "<devMode>True</devMode>").Replace("<screenWidth>$($settings.playing_screen_witdh)</screenWidth>", "<screenWidth>$($settings.modding_screen_witdh)</screenWidth>").Replace("<screenHeight>$($settings.playing_screen_height)</screenHeight>", "<screenHeight>$($settings.modding_screen_height)</screenHeight>").Replace("<fullscreen>True</fullscreen>", "<fullscreen>False</fullscreen>") | Set-Content $prefsFile
	}

	Start-Sleep -Seconds 2
	$applicationPath = $settings.steam_path
	$arguments = "-applaunch 294100"
	Start-Process -FilePath $applicationPath -ArgumentList $arguments
}

# Main mod-updating function
# Goes through all xml-files from current directory and replaces old strings/properties/valuenames.
# Can be run with the -Test parameter to just return a report of stuff that need updating, this can
# be useful to run first when starting with a mod update to see if there is a need for creating a 
# separate 1.1-folder.
function Update-Defs {
	param([switch]$Test)
	$currentDirectory = (Get-Location).Path
	if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
		Write-Host "Can only be run from somewhere under $localModFolder, exiting"
		return			
	}
	$files = Get-ChildItem *.xml -Recurse
	$replacements = Get-Content $replacementsFile
	foreach($file in $files) {
		$fileContent = Get-Content -path $file.FullName -Raw
		$xmlRemove = @()
		$output = ""
		foreach($row in $replacements) {
			if($row.Length -eq 0) {
				continue
			}
			if($row.StartsWith("#")) {
				continue
			}
			$type = $row.Split("|")[0]
			$searchText = $row.Split("|")[1]
			if($row.Split("|").Length -eq 3) {
				$replaceText = $row.Split("|")[2]
			} else {
				$replaceText = ""
			}
			if($type -eq "p") {		# Property
				$exists = $fileContent | Select-String -Pattern "<$searchText>" -AllMatches -CaseSensitive
				if($exists.Matches.Count -eq 0) {
					continue
				}
				if($replaceText.Length -gt 0) {
					$output += "`n$($exists.Matches.Count): REPLACE PROPERTY $searchText WITH $replaceText"
				} else {
					$output += "`n$($exists.Matches.Count): REMOVE PROPERTY $searchText"
				}
				if($Test) {
					continue
				}
				if($replaceText.Length -gt 0) {					
					$fileContent = $fileContent.Replace("<$searchText>", "<$replaceText>").Replace("</$searchText>", "</$replaceText>")
				} else {
					$xmlRemove += $searchText
				}
				continue
			}
			if($type -eq "v") {		# Value
				$exists = $fileContent | Select-String -Pattern ">$searchText<" -AllMatches -CaseSensitive
				if($exists.Matches.Count -eq 0) {
					continue
				}
				$output += "`n$($exists.Matches.Count): REPLACE VALUE $searchText WITH $replaceText"
				if($Test) {
					continue
				}
				$fileContent = $fileContent.Replace(">$searchText<", ">$replaceText<")
				continue
			}
			if($type -eq "s") {		#String
				$exists = $fileContent | Select-String -Pattern "$searchText" -AllMatches -CaseSensitive
				if($exists.Matches.Count -eq 0) {
					continue
				}
				$output += "`n$($exists.Matches.Count): REPLACE STRING $searchText WITH $replaceText"
				if($Test) {
					continue
				}
				$fileContent = $fileContent.Replace($searchText, $replaceText)
				continue
			}
		}
		if($output) {
			Write-Host "$($file.BaseName)`n$output`n"
		}
		try {
			[xml]$xmlContent = $fileContent
		} catch {
			"`n$($file.FullName) could not be read as xml."
			Write-Host $_
			continue
		}
		$firstNode = $xmlContent.ChildNodes[1]
		if($firstNode.Name -ne "Defs" -and $file.FullName.Contains("\Defs\")) {
			$output += "`nREPLACE $($firstNode.Name) WITH Defs"
			$newNode = $xmlContent.CreateElement('Defs')
			while($null -ne $firstNode.FirstChild) {
				[void]$newNode.AppendChild($firstNode.FirstChild)
			}
			[void]$xmlContent.RemoveChild($firstNode)
			[void]$xmlContent.AppendChild($newNode)
		}

		if($Test) {
			continue
		}
		foreach($property in $xmlRemove) {
			if($fileContent -match "<$property>") {				
				$xmlContent.SelectNodes("//$property") | ForEach-Object { $_.ParentNode.RemoveChild($_) } | Out-Null
			}
		}
		$xmlContent.Save($file.FullName)
	}
}

# Git-fetching function
# A simple function to update a local mod from a remote git server
function Get-LatestGitVersion {
	$currentDirectory = (Get-Location).Path
	if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
		Write-Host "Can only be run from somewhere under $localModFolder, exiting"
		return			
	}
	$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	$modFolder = "$localModFolder\$modName"
	Set-Location $modFolder
	if(Test-Path "$modFolder\.git") {
		git pull origin master | Out-Null
	} else {
		$path = Read-Host "URL for the project"
		git clone $path $modFolder
	}
}

# XML-cleaning function
# Resaves all XML-files using validated XML. Also warns if there seems to be overwritten base-defs
# Useful to run on a mod to remove all extra whitespaces and redundant formatting
function Set-ModXml {
	$currentDirectory = (Get-Location).Path
	if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
		Write-Host "Can only be run from somewhere under $localModFolder, exiting"
		return			
	}
	$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	$modFolder = "$localModFolder\$modName"
	
	# Clean up XML-files
	$files = Get-ChildItem "$modFolder\*.xml" -Recurse
	foreach($file in $files) {
		try {
			[xml]$fileContent = Get-Content -path $file.FullName -Raw
		} catch {
			"`n$($file.FullName) could not be read as xml."
			Write-Host $_
			continue
		}
		$allBases = $fileContent.Defs.ChildNodes | Where-Object -Property Name -Match "Base$"
		$baseWarnings = @()
		foreach($def in $allBases) {
			if($null -eq $def.ParentName -and $def.Abstract -eq $true) {
				$baseWarnings += $def.Name
			}
		}
		if($baseWarnings.Count -gt 0) {
			$applicationPath = $settings.text_editor_path
			$arguments = """$($file.FullName)"""
			Start-Process -FilePath $applicationPath -ArgumentList $arguments
			Write-Host "`n$($file.FullName)"
			Write-Host "Possible redundant base-classes: $($baseWarnings -join ", ")"
		}
		$fileContent.Save($file.FullName)
	}
}

# Function for pushing new version of mod to git-repo
# On first publish adds gitignore-file, PublisherPlus-file, Licence
# Updates the Manifest, ModSyncfile with new version
# Generates the default english-translation files (useful for translators as template)
# Downloads the current git-hub version to a staging directory
# Copies the current version of the mod to the staging directory
# Pushes the updated source to github and generates a new release
function Publish-Mod {
	[CmdletBinding()]
	param (		
		[switch]$SelectFolder
	)
	if($SelectFolder) {
		$modFolder = Get-Folder 
		if(-not $modFolder) {
			Write-Host "No folder selected, exiting"
			return
		}
		$modName = Split-Path -Leaf $modFolder
	} else {
		$currentDirectory = (Get-Location).Path
		if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
			Write-Host "Can only be run from somewhere under $localModFolder, exiting"
			return			
		}
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
		$modFolder = "$localModFolder\$modName"
	}
	
	$modNameClean = $modName.Replace("+", "Plus")
	$stagingDirectory = $settings.mod_staging_folder
	$rootFolder = Split-Path $stagingDirectory
	$manifestFile = "$modFolder\About\Manifest.xml"
	$modsyncFile = "$modFolder\About\ModSync.xml"
	$aboutFile = "$modFolder\About\About.xml"
	$readmeFile = "$modFolder\README.md"
	$gitIgnorePath = "$modFolder\.gitignore"
	$modPublisherPath = "$modFolder\_PublisherPlus.xml"
	$reapplyGitignore = $false
	$gitApiToken = $settings.github_api_token

	# Clean up XML-files
	$files = Get-ChildItem "$modFolder\*.xml" -Recurse
	foreach($file in $files) {
		try {
			[xml]$fileContent = Get-Content -path $file.FullName -Raw
		} catch {
			"`n$($file.FullName) could not be read as xml."
			Write-Host $_
			return
		}
		$fileContent.Save($file.FullName)
	}

	# Generate english-language if missing
	Set-Translation -ModName $modNameClean

	# Reset Staging
	Set-Location -Path $rootFolder
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse
	Set-Location -Path $stagingDirectory

	# Prepare mod-directory
	$aboutContent = Get-Content $aboutFile -Raw
	$modFullName = ($aboutContent.Replace("<name>", "|").Split("|")[1].Split("<")[0])

	# Mod Manifest
	if(-not (Test-Path $manifestFile)) {
		Copy-Item -Path $manifestTemplate $manifestFile -Force | Out-Null
		((Get-Content -path $manifestFile -Raw).Replace("[modname]",$modNameClean).Replace("[username]",$settings.github_username)) | Set-Content -Path $manifestFile
	} else {
		$manifestContent = Get-Content -path $manifestFile -Raw
		$currentIdentifier = $manifestContent.Replace("<identifier>", "|").Split("|")[1].Split("<")[0]
		if($currentIdentifier -ne $modNameClean) {
			((Get-Content -path $manifestFile -Raw).Replace($currentIdentifier,$modNameClean)) | Set-Content -Path $manifestFile
		}
	}
	$version = [version]((Get-Content $manifestFile -Raw).Replace("<version>", "|").Split("|")[1].Split("<")[0])
	if(Test-Path $licenseFile) {
		if(Test-Path $modFolder\LICENSE) {
			Remove-Item -Path "$modFolder\LICENSE" -Force
		}
		if(-not (Test-Path $modFolder\LICENSE.md)) {
			Copy-Item -Path $licenseFile $modFolder\LICENSE.md -Force | Out-Null
		} else {
			if((Get-Item -Path $modFolder\LICENSE.md).LastAccessTime -lt (Get-Item $licenseFile).LastAccessTime) {
				Copy-Item -Path $licenseFile $modFolder\LICENSE.md -Force | Out-Null
			}
		}
	}
	if(-not (Test-Path $gitIgnorePath) -or ((Get-Item $gitignoreTemplate).LastWriteTime -gt (Get-Item $gitIgnorePath).LastWriteTime)) {
		Copy-Item -Path $rootFolder\.gitignore $gitIgnorePath -Force | Out-Null
		$reapplyGitignore = $true
	} 
	if((Test-Path $modSyncTemplate) -and -not (Test-Path $modsyncFile)) {
		New-ModSyncFile -targetPath $modsyncFile -modWebPath $modNameClean -modname $modFullName -version $version.ToString()
	}
	if((Test-Path $publisherPlusTemplate) -and -not (Test-Path $modPublisherPath)) {
		Copy-Item -Path $publisherPlusTemplate $modPublisherPath -Force | Out-Null
		((Get-Content -path $modPublisherPath -Raw).Replace("[modpath]",$modFolder)) | Set-Content -Path $modPublisherPath
	}

	# Create repo if does not exists
	if(Get-RepositoryStatus -repositoryName $modNameClean) {
		$message = Read-Host "Commit-Message"
		$oldVersion = "$($version.Major).$($version.Minor).$($version.Build)"
		$newVersion = "$($version.Major).$($version.Minor).$($version.Build + 1)"
		((Get-Content -path $manifestFile -Raw).Replace($oldVersion,$newVersion)) | Set-Content -Path $manifestFile
		((Get-Content -path $modsyncFile -Raw).Replace($oldVersion,$newVersion)) | Set-Content -Path $modsyncFile
	} else {
		Read-Host "Repository could not be found, create $modNameClean?"
		$repoData = @{
			name = $modNameClean;
			visibility = "public";
			auto_init = "true"
		}
		$repoParams = @{
			Uri = "https://api.github.com/user/repos";
			Method = 'POST';
			Headers = @{
			Authorization = 'Basic ' + [Convert]::ToBase64String(
			[Text.Encoding]::ASCII.GetBytes($gitApiToken + ":x-oauth-basic"));
			}
			ContentType = 'application/json';
			Body = (ConvertTo-Json $repoData -Compress)
		}
		Write-Host "Creating repo"
		Invoke-RestMethod @repoParams | Out-Null
		Start-Sleep -Seconds 1
		Write-Host "Done"
		$message = "First publish"
		$newVersion = "$($version.Major).$($version.Minor).$($version.Build)"
	}

	# Clone current repository to staging
	git clone https://github.com/$($settings.github_username)/$modNameClean

	# Copy replace modfiles
	if(-not (Test-Path $readmeFile) -or (Get-Content $readmeFile).Count -lt 10) {
	"# $modNameClean`n`r" > $readmeFile
	((Get-Content $aboutFile -Raw).Replace("<description>", "|").Split("|")[1].Split("<")[0]) >> $readmeFile
	}
	robocopy $modFolder $stagingDirectory\$modNameClean /MIR /w:10 /XD .git
	Set-Location -Path $stagingDirectory\$modNameClean

	# Reapply gitignore-file if necessary
	if($reapplyGitignore) {
		git rm -r --cached .
	}

	git add .
	git commit -m $message
	git push origin master
	git tag -a $newVersion -m $message master
	git push --tags

	$releaseData = @{
		tag_name = $newVersion;
		name = $message;
	}
	$releaseParams = @{
		Uri = "https://api.github.com/repos/$($settings.github_username)/$modNameClean/releases";
		Method = 'POST';
		Headers = @{
		Authorization = 'Basic ' + [Convert]::ToBase64String(
		[Text.Encoding]::ASCII.GetBytes($gitApiToken + ":x-oauth-basic"));
		}
		ContentType = 'application/json';
		Body = (ConvertTo-Json $releaseData -Compress)
	}
	Invoke-RestMethod @releaseParams | Out-Null
	Write-Host "Published $modName!"
	Set-Location $modFolder
}

# Helper function
# Generates default language files for english
function Set-Translation {
	param (
		[string] $ModName
	)
	$rimTransExe = $settings.rimtrans_path
	$templateFile = $settings.rimtrans_template
	$currentFile = $templateFile.Replace(".xml", "_current.xml")
	$command = "-p:$currentFile"

	Write-Host "Generating default language-data"

	(Get-Content $templateFile -Raw).Replace("[modpath]", "$localModFolder\$ModName") | Out-File $currentFile -Encoding utf8
	
	$process = Start-Process -FilePath $rimTransExe -ArgumentList $command -PassThru 
	$wshell = New-Object -ComObject wscript.shell;
	$wshell.AppActivate('RimTrans')
	$wshell.SendKeys('{ENTER}')
	while(-not $process.HasExited) { Start-Sleep -Milliseconds 200 }
	Write-Host "Generation done"	
	Remove-Item -Path $currentFile -Force
}