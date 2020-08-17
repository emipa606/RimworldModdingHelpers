# First get the settings from the json-file
$settingsFilePath = "$PSScriptRoot\settings.json"
if(-not (Test-Path $settingsFilePath)) {
	Write-Host "Could not find settingsfile: $settingsFilePath, exiting."
	return
}
$Global:settings = Get-Content -Path $settingsFilePath -raw -Encoding UTF8 | ConvertFrom-Json
$Global:localModFolder = "$($settings.rimworld_folder_path)\Mods"
$Global:playingModsConfig = "$PSScriptRoot\ModsConfig_Playing.xml"
$Global:moddingModsConfig = "$PSScriptRoot\ModsConfig_Modding.xml"
$Global:testingModsConfig = "$PSScriptRoot\ModsConfig_Testing.xml"
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
$Global:rimTransTemplate = "$PSScriptRoot\$($settings.rimtrans_template)"
$Global:updatefeaturesTemplate = "$PSScriptRoot\$($settings.updatefeatures_template)"
$Global:modSyncTemplate = "$PSScriptRoot\$($settings.modsync_template)"
$Global:licenseFile = "$PSScriptRoot\$($settings.license_file)"
$Global:discordUpdateMessage = "$PSScriptRoot\$($settings.discord_update_message)"
$Global:discordPublishMessage = "$PSScriptRoot\$($settings.discord_publish_message)"
$Global:discordUpdateHookUrl = $settings.discord_update_hook_url
$Global:discordPublishHookUrl = $settings.discord_publish_hook_url

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

	try {
		# We then get a response from the site.
		$HTTP_Response = $HTTP_Request.GetResponse()

		# We then get the HTTP code as an integer.
		$HTTP_Status = [int]$HTTP_Response.StatusCode

		If ($null -ne $HTTP_Response) { 
			$HTTP_Response.Close() 
		}

		If ($HTTP_Status -eq 200) {
			return $true
		}
	} catch {
		return $false
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
  if(-not (Test-Path $modSyncTemplate)) {
	  Write-Host "Cound not find ModSync-template: $($modSyncTemplate), skipping."
	  return
  }
  Copy-Item $modSyncTemplate $targetPath -Force
  ((Get-Content -path $targetPath -Raw -Encoding UTF8).Replace("[guid]", [guid]::NewGuid().ToString())) | Set-Content -Path $targetPath
  ((Get-Content -path $targetPath -Raw -Encoding UTF8).Replace("[modname]", $modname)) | Set-Content -Path $targetPath
  ((Get-Content -path $targetPath -Raw -Encoding UTF8).Replace("[version]", $version)) | Set-Content -Path $targetPath
  ((Get-Content -path $targetPath -Raw -Encoding UTF8).Replace("[username]", $settings.github_username)) | Set-Content -Path $targetPath
  ((Get-Content -path $targetPath -Raw -Encoding UTF8).Replace("[modwebpath]", $modWebPath)) | Set-Content -Path $targetPath  
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
	$modId = Get-Content $modFileId -Raw -Encoding UTF8
	$applicationPath = $settings.browser_path
	$arguments = "https://steamcommunity.com/sharedfiles/filedetails/?id=$modId"
	Start-Process -FilePath $applicationPath -ArgumentList $arguments
	Start-Sleep -Seconds 1
	Remove-Item "$localModFolder\$modName\debug.log" -Force -ErrorAction SilentlyContinue
}

# Adds an update post to the mod
# If HugsLib is loaded this will be shown if new to user
function Set-ModUpdateFeatures {
	param (
		[string] $ModName
	)

	Write-Host "Add update-message? Write the message, two blank rows ends message. To skip just press enter.'"
	$continueMessage = $true
	$currentNews = @()
	$lastRow = ""
	while ($continueMessage) {		
		$newsRow = Read-Host
		if($newsRow -eq "" -and $currentNews.Count -eq 0) {
			return
		}
		if($newsRow -eq "" -and $lastRow -eq "") {
			$continueMessage = $false
			continue
		}
		$currentNews += $newsRow
		$lastRow = $newsRow
	}

	$news = $currentNews -join "`r`n"

	if(-not (Test-Path "$localModFolder\$modName\News")) {
		New-Item -Path "$localModFolder\$modName\News" -ItemType Directory | Out-Null
	}
	$modFileId = "$localModFolder\$modName\About\PublishedFileId.txt"
	$modId = Get-Content $modFileId -Raw -Encoding UTF8
	$updatefeaturesFileName = Split-Path $updatefeaturesTemplate -Leaf
	if(-not (Test-Path "$localModFolder\$modName\News\$updatefeaturesFileName")) {
		(Get-Content -Path $updatefeaturesTemplate -Raw -Encoding UTF8).Replace("[modname]", $ModName).Replace("[modid]", $modId) | Out-File "$localModFolder\$modName\News\$updatefeaturesFileName"
	}

	$defaultNewsObject = "	<HugsLib.UpdateFeatureDef ParentName=""UpdateFeatureBase"">
		<defName>[newsid]</defName>
		<assemblyVersion>[version]</assemblyVersion>
		<content>[news]</content>
	</HugsLib.UpdateFeatureDef>
</Defs>"
	$manifestFile = "$localModFolder\$modName\About\Manifest.xml"
	$version = ((Get-Content $manifestFile -Raw -Encoding UTF8).Replace("<version>", "|").Split("|")[1].Split("<")[0])

	$newsObject = $defaultNewsObject.Replace("[newsid]", "$($ModName.Replace(" ", "_"))_$($version.Replace(".", "_"))")
	$newsObject = $newsObject.Replace("[version]", $version).Replace("[news]", $news)

	(Get-Content -Path "$localModFolder\$modName\News\$updatefeaturesFileName" -Raw -Encoding UTF8).Replace("</Defs>", $newsObject) | Out-File "$localModFolder\$modName\News\$updatefeaturesFileName"
	Write-Host "Added update news"
}


# Adds an changelog post to the mod
function Set-ModChangeNote {
	param (
		[string] $ModName,
		[string] $Changenote
	)
	$baseLine = "# Changelog for $ModName"
	$changelogFilePath = "$localModFolder\$ModName\About\Changelog.txt"
	if(-not (Test-Path $changelogFilePath)) {
		$baseLine  | Out-File $changelogFilePath
	}

	$replaceLine = "$baseLine

$Changenote
"
	(Get-Content -Path $changelogFilePath -Raw -Encoding UTF8).Replace($baseLine, $replaceLine) | Out-File $changelogFilePath -NoNewline
	Write-Host "Added changelog"
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
	param ([switch]$play,
			[string]$testMod,
			[string]$testAuthor)

	if($test -and $play) {
		Write-Host "You cant test and play at the same time."
		return
	}
	
	$prefsFile = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\Prefs.xml"
	$modFile = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\ModsConfig.xml"

	$currentActiveMods = Get-Content $modFile -Encoding UTF8
	if($currentActiveMods.Length -gt 20) {
		$currentActiveMods | Set-Content -Path $playingModsConfig -Encoding UTF8
	} else {
		$currentActiveMods | Set-Content -Path $moddingModsConfig -Encoding UTF8
	}
	Stop-Process -Name "RimWorldWin64" -ErrorAction SilentlyContinue

	if($testAuthor) {
		Copy-Item $testingModsConfig $modFile -Confirm:$false		
		$modsToTest = Get-AllModsFromAuthor -author $testAuthor -onlyPublished
		$modIdentifiersPrereq = ""
		$modIdentifiers = ""
		foreach($modname in $modsToTest) {
			$identifiersToAdd = Get-IdentifiersFromMod -modname $modname
			if($identifiersToAdd.Length -eq 0) {
				Write-Host "No mod identifiers found, exiting."
				return
			}
			if($identifiersToAdd.Count -eq 1) {
				Write-Host "Adding $identifiersToAdd as mod to test"
				$modIdentifiers += "<li>$identifiersToAdd</li>"
			} else {
				foreach($identifier in $identifiersToAdd) {
					if($modIdentifiersPrereq.Contains($identifier) -or $modIdentifiers.Contains($identifier) ) {
						continue
					}
					if($identifier -eq $identifiersToAdd[$identifiersToAdd.Length - 1]) {
						Write-Host "Adding $identifier as mod to test"
						$modIdentifiers += "<li>$identifier</li>"
					} else {
						Write-Host "Adding $identifier as prerequirement"
						$modIdentifiersPrereq += "<li>$identifier</li>"
					}
				}
			}
		}		
		(Get-Content $modFile -Raw -Encoding UTF8).Replace("</activeMods>", "$modIdentifiersPrereq</activeMods>").Replace("</activeMods>", "$modIdentifiers</activeMods>") | Set-Content $modFile
		(Get-Content $prefsFile -Raw -Encoding UTF8).Replace("<resetModsConfigOnCrash>True</resetModsConfigOnCrash>", "<resetModsConfigOnCrash>False</resetModsConfigOnCrash>").Replace("<devMode>False</devMode>", "<devMode>True</devMode>").Replace("<screenWidth>$($settings.playing_screen_witdh)</screenWidth>", "<screenWidth>$($settings.modding_screen_witdh)</screenWidth>").Replace("<screenHeight>$($settings.playing_screen_height)</screenHeight>", "<screenHeight>$($settings.modding_screen_height)</screenHeight>").Replace("<fullscreen>True</fullscreen>", "<fullscreen>False</fullscreen>") | Set-Content $prefsFile
	}
	if($testMod) {
		Copy-Item $testingModsConfig $modFile -Confirm:$false		
		$identifiersToAdd = Get-IdentifiersFromMod -modname $testMod
		if($identifiersToAdd.Length -eq 0) {
			Write-Host "No mod identifiers found, exiting."
			return
		}
		$modIdentifiers = ""
		if($identifiersToAdd.Count -eq 1) {
			Write-Host "Adding $identifiersToAdd as mod to test"
			$modIdentifiers += "<li>$identifiersToAdd</li>"
		} else {			
			foreach($identifier in $identifiersToAdd) {
				if($identifier -eq $identifiersToAdd[$identifiersToAdd.Length - 1]) {
					Write-Host "Adding $identifier as mod to test"
				} else {
					Write-Host "Adding $identifier as prerequirement"
				}
				$modIdentifiers += "<li>$identifier</li>"
			}	
		}	
		(Get-Content $modFile -Raw -Encoding UTF8).Replace("</activeMods>", "$modIdentifiers</activeMods>") | Set-Content $modFile
		(Get-Content $prefsFile -Raw -Encoding UTF8).Replace("<resetModsConfigOnCrash>True</resetModsConfigOnCrash>", "<resetModsConfigOnCrash>False</resetModsConfigOnCrash>").Replace("<devMode>False</devMode>", "<devMode>True</devMode>").Replace("<screenWidth>$($settings.playing_screen_witdh)</screenWidth>", "<screenWidth>$($settings.modding_screen_witdh)</screenWidth>").Replace("<screenHeight>$($settings.playing_screen_height)</screenHeight>", "<screenHeight>$($settings.modding_screen_height)</screenHeight>").Replace("<fullscreen>True</fullscreen>", "<fullscreen>False</fullscreen>") | Set-Content $prefsFile
	}
	if($play) {
		Copy-Item $playingModsConfig $modFile -Confirm:$false
		(Get-Content $prefsFile -Raw -Encoding UTF8).Replace("<devMode>True</devMode>", "<devMode>False</devMode>").Replace("<screenWidth>$($settings.modding_screen_witdh)</screenWidth>", "<screenWidth>$($settings.playing_screen_witdh)</screenWidth>").Replace("<screenHeight>$($settings.modding_screen_height)</screenHeight>", "<screenHeight>$($settings.playing_screen_height)</screenHeight>").Replace("<fullscreen>False</fullscreen>", "<fullscreen>True</fullscreen>") | Set-Content $prefsFile
	}
	if(-not $testMod -and -not $play -and -not $testAuthor ) {
		Copy-Item $moddingModsConfig $modFile -Confirm:$false
		(Get-Content $prefsFile -Raw -Encoding UTF8).Replace("<resetModsConfigOnCrash>True</resetModsConfigOnCrash>", "<resetModsConfigOnCrash>False</resetModsConfigOnCrash>").Replace("<devMode>False</devMode>", "<devMode>True</devMode>").Replace("<screenWidth>$($settings.playing_screen_witdh)</screenWidth>", "<screenWidth>$($settings.modding_screen_witdh)</screenWidth>").Replace("<screenHeight>$($settings.playing_screen_height)</screenHeight>", "<screenHeight>$($settings.modding_screen_height)</screenHeight>").Replace("<fullscreen>True</fullscreen>", "<fullscreen>False</fullscreen>") | Set-Content $prefsFile
	}

	Start-Sleep -Seconds 2
	$applicationPath = $settings.steam_path
	$arguments = "-applaunch 294100"
	Start-Process -FilePath $applicationPath -ArgumentList $arguments
}

# Returns an array of all mod-directories of mods by a specific author
function Get-AllModsFromAuthor {
	param ([string]$author,
			[switch]$onlyPublished)
	$allMods = Get-ChildItem -Directory $localModFolder
	$returnArray = @()
	foreach($folder in $allMods) {
		if(-not (Test-Path "$($folder.FullName)\About\About.xml")) {
			continue
		}
		if($onlyPublished -and -not (Test-Path "$($folder.FullName)\About\PublishedFileId.txt")) {
			continue
		}
		$aboutFile = "$($folder.FullName)\About\About.xml"
		if((Get-Content -path $aboutFile -Raw -Encoding UTF8).Contains("<author>$author</author>")) {
			$returnArray += $folder.Name
		}
	}
	return $returnArray
}

# Returns a list of all mods where files have been modified since the last publish.
function Get-AllNonPublishedMods {
	param ([switch]$detailed,
			[switch]$ignoreAbout)
	$allMods = Get-ChildItem -Directory $localModFolder
	$returnArray = @()
	foreach($folder in $allMods) {
		if(-not (Test-Path "$($folder.FullName)\About\ModSync.xml")) {
			continue
		}
		if(-not (Test-Path "$($folder.FullName)\About\PublishedFileId.txt")) {
			continue
		}
		$modsyncFileModified = (Get-Item "$($folder.FullName)\About\ModSync.xml").LastWriteTime

		if($ignoreAbout) {
			$newerFiles = Get-ChildItem $folder.FullName -File -Recurse -Exclude "About.xml" | Where-Object { $_.LastWriteTime -gt $modsyncFileModified.AddMinutes(5)}
		} else {
			$newerFiles = Get-ChildItem $folder.FullName -File -Recurse  | Where-Object { $_.LastWriteTime -gt $modsyncFileModified.AddMinutes(5)}
		}
		if($newerFiles.Count -gt 0) {
			$returnString = "`n$($folder.Name) has $($newerFiles.Count) files newer than publish-date"
			if($detailed) {
				$returnString += ":"
				foreach($file in $newerFiles) {
					$minutesString = "$([math]::floor(($file.LastWriteTime - $modsyncFileModified).TotalMinutes)) minutes newer"
					$returnString += "`n$($file.FullName.Replace($localModFolder, '').Replace('\$($folder.Name)', '')) - $minutesString"
				}
			}
			$returnArray += $returnString
		}		
	}
	return $returnArray
}

# Scans a mods About-file for mod-identifiers and returns an array of them, with the selected mods identifier last
function Get-IdentifiersFromMod {
	param ([string]$modname)
	$aboutFile = "$localModFolder\$modname\About\About.xml"
	if(-not (Test-Path $aboutFile)) {
		Write-Host "Could not find About-file for mod named $modname"
		return @()
	}
	$aboutFileContent = Get-Content $aboutFile -Raw -Encoding UTF8
	$identifiersList = $aboutFileContent.Replace("<packageId>", "|").Split("|")
	$identifiersToAdd = @()
	$identifiersToIgnore = "brrainz.harmony", "unlimitedhugs.hugslib", "ludeon.rimworld", "ludeon.rimworld.royalty"
	foreach($identifier in $identifiersList) {
		$identifierString = $identifier.Split("<")[0].ToLower()
		if(-not ($identifierString.Contains(".")) -or $identifiersToIgnore.Contains($identifierString) -or $identifierString.Contains(" ")) {
			continue
		}
		if($identifiersToAdd.Contains($identifierString)) {
			$identifiersToAdd = $identifiersToAdd | Where-Object { $_ -ne $identifierString }
		} else {
			$identifiersToAdd += $identifierString
		}
	}
	[array]::Reverse($identifiersToAdd)
	return $identifiersToAdd
}

# Updates a mods content to a new version
# Looks for the previous versions sub-folder and clones it to the new version if found
# Adds the new version to the supported versions in the About-file
# Updates references in any C# projects so the dll-file is created in the new folder
function Set-ModIncrement {
	param([switch]$Test)
	$currentDirectory = (Get-Location).Path
	if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
		Write-Host "Can only be run from somewhere under $localModFolder, exiting"
		return			
	}	
	$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	$modFolder = "$localModFolder\$modName"
	$versionFile = "$localModFolder\..\Version.txt"
	$aboutFile = "$modFolder\About\About.xml"
	$currentVersion = [version]([regex]::Match((Get-Content $versionFile -Raw -Encoding UTF8), "[0-9]+\.[0-9]+")).Value
	$currentVersionString = "$($currentVersion.Major).$($currentVersion.Minor)"
	if((Get-Content -path $aboutFile -Raw -Encoding UTF8).Contains("<li>$currentVersionString</li>")) {
		Write-Host "Mod already has support for $currentVersionString according to the About-file"
		return
	}

	$lastVersion = "$($currentVersion.Major).$($currentVersion.Minor - 1)"
	Write-Host "Current game version: $currentVersionString, looking for $lastVersion-folder"
	$cloneFromPreviousVersion = Test-Path "$modFolder\$lastVersion"
	if($cloneFromPreviousVersion) {
		Write-Host "$lastVersion-folder found, will clone it to $currentVersionString"
		if(-not $Test) {
			Copy-Item -Path "$modFolder\$lastVersion" -Destination "$modFolder\$currentVersionString" -Recurse -Force
		}
	} else {
		Write-Host "No $lastVersion-folder found, will not generate new version-dir"
	}

	Write-Host "Will add $currentVersionString to supported versions in About.xml"
	if(-not $Test) {
		((Get-Content -path $aboutFile -Raw -Encoding UTF8).Replace("</supportedVersions>","<li>$currentVersionString</li></supportedVersions>")) | Set-Content -Path $aboutFile
		[xml]$fileContent = Get-Content -path $aboutFile -Raw -Encoding UTF8
		$fileContent.Save($aboutFile)
	}
	
	if(Test-Path "$modFolder\Source") {		
		$csprojFile = Get-ChildItem "$modFolder\Source\*.csproj" -Recurse
		if($csprojFile.Length -gt 0) {
			Write-Host "Mod has VS project to update"
			foreach ($file in $csprojFile) {
				Write-Host "Updating $($file.FullName.Replace($modFolder, "."))"
				if(-not $Test) {
					(Get-Content -path $file.FullName -Raw -Encoding UTF8).Replace("$lastVersion\Assemblies", "$currentVersionString\Assemblies") | Set-Content -Path $file.FullName
					[xml]$fileContent = Get-Content -path $file.FullName -Raw -Encoding UTF8
					$fileContent.Save($file.FullName)
				}
			}
		}
	}
	Write-Host "Done"
}

# Wrapper for the different functions needed for updating mods
function Update-NextMod {
	Set-Location $localModFolder
	Get-NotUpdatedMods -FirstOnly
	if((Get-Location).Path -eq $localModFolder) {
		Write-Host "No mods need updating"
		return
	}
	$continue = Read-Host "$(Split-Path (Get-Location).Path -Leaf) - Continue? (Blank yes)"
	if($continue.Length -gt 0) {
		return
	}
	Set-ModIncrement
	Test-Mod
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
	$replacements = Get-Content $replacementsFile -Encoding UTF8
	$infoBlob = ""
	foreach($file in $files) {
		$fileContent = Get-Content -path $file.FullName -Raw -Encoding UTF8
		if(-not $fileContent.StartsWith("<?xml")) {
			$fileContent = "<?xml version=""1.0"" encoding=""utf-8""?>" + $fileContent
		}
		$xmlRemove = @()
		$output = ""
		$localInfo = ""
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
			if($type -eq "p" -or $type -eq "pi") {		# Property
				$exists = $fileContent | Select-String -Pattern "<$searchText>" -AllMatches -CaseSensitive
				if($exists.Matches.Count -eq 0) {
					continue
				}
				if($type -eq "pi") {
					$localInfo += "`n$($exists.Matches.Count): INFO PROPERTY $searchText - $replaceText"
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
			if($type -eq "v" -or $type -eq "vi") {		# Value
				$exists = $fileContent | Select-String -Pattern ">$searchText<" -AllMatches -CaseSensitive
				if($exists.Matches.Count -eq 0) {
					continue
				}				
				if($type -eq "vi") {
					$localInfo += "`n$($exists.Matches.Count): INFO VALUE $searchText - $replaceText"
					continue
				}
				$output += "`n$($exists.Matches.Count): REPLACE VALUE $searchText WITH $replaceText"
				if($Test) {
					continue
				}
				$fileContent = $fileContent.Replace(">$searchText<", ">$replaceText<")
				continue
			}
			if($type -eq "s" -or $type -eq "si") {		#String
				$exists = $fileContent | Select-String -Pattern "$searchText" -AllMatches -CaseSensitive
				if($exists.Matches.Count -eq 0) {
					continue
				}			
				if($type -eq "si") {
					$localInfo += "`n$($exists.Matches.Count): INFO STRING $searchText - $replaceText"
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
		if($localInfo -ne "") {
			$infoBlob += "$($file.BaseName)`n$localInfo`n"
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
	if($infoBlob -ne "") {
		Write-Host $infoBlob.Replace("#n", "`n")
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
		$fileContentRaw = Get-Content -path $file.FullName -Raw -Encoding UTF8		
		if(-not $fileContent.StartsWith("<?xml")) {
			$fileContentRaw = "<?xml version=""1.0"" encoding=""utf-8""?>" + $fileContentRaw
		}
		try {
			[xml]$fileContent = $fileContentRaw
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
		$fileContentRaw = Get-Content -path $file.FullName -Raw -Encoding UTF8		
		if(-not $fileContentRaw.StartsWith("<?xml")) {
			$fileContentRaw = "<?xml version=""1.0"" encoding=""utf-8""?>" + $fileContentRaw
		}
		try {
			[xml]$fileContent = $fileContentRaw
		} catch {
			"`n$($file.FullName) could not be read as xml."
			Write-Host $_
			return
		}
		$fileContent.Save($file.FullName)
	}

	# Generate english-language if missing
	Set-Translation -ModName $modName

	# Reset Staging
	Set-Location -Path $rootFolder
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse
	Set-Location -Path $stagingDirectory

	# Prepare mod-directory
	$aboutContent = Get-Content $aboutFile -Raw -Encoding UTF8
	$modFullName = ($aboutContent.Replace("<name>", "|").Split("|")[1].Split("<")[0])

	# Mod Manifest
	if(-not (Test-Path $manifestFile)) {
		Copy-Item -Path $manifestTemplate $manifestFile -Force | Out-Null
		((Get-Content -path $manifestFile -Raw -Encoding UTF8).Replace("[modname]",$modNameClean).Replace("[username]",$settings.github_username)) | Set-Content -Path $manifestFile
	} else {
		$manifestContent = Get-Content -path $manifestFile -Raw -Encoding UTF8
		$currentIdentifier = $manifestContent.Replace("<identifier>", "|").Split("|")[1].Split("<")[0]
		if($currentIdentifier -ne $modNameClean) {
			((Get-Content -path $manifestFile -Raw -Encoding UTF8).Replace($currentIdentifier,$modNameClean)) | Set-Content -Path $manifestFile
		}
	}
	$version = [version]((Get-Content $manifestFile -Raw -Encoding UTF8).Replace("<version>", "|").Split("|")[1].Split("<")[0])
	if(Test-Path $licenseFile) {
		if(Test-Path $modFolder\LICENSE) {
			Remove-Item -Path "$modFolder\LICENSE" -Force
		}
		if(-not (Test-Path $modFolder\LICENSE.md)) {
			Copy-Item -Path $licenseFile $modFolder\LICENSE.md -Force | Out-Null
		} else {
			if((Get-Item -Path $modFolder\LICENSE.md).LastWriteTime -lt (Get-Item $licenseFile).LastWriteTime) {
				Copy-Item -Path $licenseFile $modFolder\LICENSE.md -Force | Out-Null
			}
		}
	}
	if(-not (Test-Path $gitIgnorePath) -or ((Get-Item $gitignoreTemplate).LastWriteTime -gt (Get-Item $gitIgnorePath).LastWriteTime)) {
		Copy-Item -Path $gitignoreTemplate $gitIgnorePath -Force | Out-Null
		$reapplyGitignore = $true
	} 
	if((Test-Path $modSyncTemplate) -and -not (Test-Path $modsyncFile)) {
		New-ModSyncFile -targetPath $modsyncFile -modWebPath $modNameClean -modname $modFullName -version $version.ToString()
	}
	if((Test-Path $publisherPlusTemplate) -and -not (Test-Path $modPublisherPath)) {
		Copy-Item -Path $publisherPlusTemplate $modPublisherPath -Force | Out-Null
		((Get-Content -path $modPublisherPath -Raw -Encoding UTF8).Replace("[modpath]",$modFolder)) | Set-Content -Path $modPublisherPath
	}

	# Create repo if does not exists
	if(Get-RepositoryStatus -repositoryName $modNameClean) {
		$message = Read-Host "Commit-Message"
		$oldVersion = "$($version.Major).$($version.Minor).$($version.Build)"
		$newVersion = "$($version.Major).$($version.Minor).$($version.Build + 1)"
		((Get-Content -path $manifestFile -Raw -Encoding UTF8).Replace($oldVersion,$newVersion)) | Set-Content -Path $manifestFile
		((Get-Content -path $modsyncFile -Raw -Encoding UTF8).Replace($oldVersion,$newVersion)) | Set-Content -Path $modsyncFile
		Set-ModUpdateFeatures -ModName $modNameClean
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

	$version = [version]((Get-Content $manifestFile -Raw -Encoding UTF8).Replace("<version>", "|").Split("|")[1].Split("<")[0])
	Set-ModChangeNote -ModName $modName -Changenote "$version - $message"

	# Clone current repository to staging
	git clone https://github.com/$($settings.github_username)/$modNameClean

	# Copy replace modfiles
	if(-not (Test-Path $readmeFile) -or (Get-Content $readmeFile).Count -lt 10) {
	"# $modNameClean`n`r" > $readmeFile
	((Get-Content $aboutFile -Raw -Encoding UTF8).Replace("<description>", "|").Split("|")[1].Split("<")[0]) >> $readmeFile
	}
	robocopy $modFolder $stagingDirectory\$modNameClean /MIR /w:10 /XD .git /NFL /NDL /NJH /NJS /NP
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
	$createdRelease = Invoke-RestMethod @releaseParams
	
	Get-ZipFile -modname $modName -filename "$($modNameClean)_$newVersion.zip"
	$zipFile = Get-Item "$localModFolder\$modname\$($modNameClean)_$newVersion.zip"
	$fileName = $zipFile.Name
	$uploadParams = @{
		Uri = "https://uploads.github.com/repos/$($settings.github_username)/$modNameClean/releases/$($createdRelease.id)/assets?name=$fileName&label=$fileName";
		Method = 'POST';
		Headers = @{
			Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($gitApiToken + ":x-oauth-basic"));
		}
	}

	$uploadedFile = Invoke-RestMethod @uploadParams -InFile $zipFile.FullName -ContentType "application/zip"
	Write-Host "Zip-file status: $($uploadedFile.state)"
	Remove-Item $zipFile.FullName -Force

	Set-Location $modFolder
	if($message -ne "First publish") {
		Push-UpdateNotification -Changenote "$version - $message"
	}
	Write-Host "Published $modName!"
}

# Generates a zip-file of a mod, looking in the _PublisherPlus.xml for exlusions
function Get-ZipFile {
	param([string]$modname,
		[string]$filename)
	$exclusions = "$localModFolder\$modname\_PublisherPlus.xml"
	$exclusionsToAdd = " -xr!""_PublisherPlus.xml"""
	if((Test-Path $exclusions)) {
		$splittedContent = (Get-Content $exclusions -Raw -Encoding UTF8).Replace("<exclude>", "|").Split("|")
		for ($i = 1; $i -lt $splittedContent.Count; $i++) {
			$excusion = $splittedContent[$i].Replace("</exclude>", "|").Split("|")[0].Replace("$localModFolder\$modname\", "")
			$exclusionsToAdd += " -xr!""$excusion"""
		}
	}
	$outFile = "$localModFolder\$modname\$filename"
	$7zipPath = $settings.zip_path
	$arguments = "a ""$outFile"" ""$localModFolder\$modname\"" -r -bd $exclusionsToAdd "
	Start-Process -FilePath $7zipPath -ArgumentList $arguments -Wait
}

# Simple push function for git
function Push-ModContent {
	$message = Read-Host "Commit-Message"
	git add .
	git commit -m $message
	git push origin master
}

# Test the mod in the current directory
function Test-Mod {
	$currentDirectory = (Get-Location).Path
	if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
		Write-Host "Can only be run from somewhere under $localModFolder, exiting"
		return			
	}
	$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	Write-Host "Testing $modName"
	Start-RimWorld -testMod $modName
}

# Returns a list of mods that has not been updated to the latest version
# With switch FirstOnly the current directory is changed to the next not-updated mod root path
function Get-NotUpdatedMods {
	param([switch]$FirstOnly)
	$versionFile = "$localModFolder\..\Version.txt"
	$currentVersion = [version]([regex]::Match((Get-Content $versionFile -Raw -Encoding UTF8), "[0-9]+\.[0-9]+")).Value
	$currentVersionString = "$($currentVersion.Major).$($currentVersion.Minor)"
	$allMods = Get-ChildItem -Directory $localModFolder
	foreach($folder in $allMods) {
		if(-not (Test-Path "$($folder.FullName)\About\PublishedFileId.txt")) {
			continue
		}
		$aboutFile = "$($folder.FullName)\About\About.xml"
		if(-not (Get-Content -path $aboutFile -Raw -Encoding UTF8).Contains("<li>$currentVersionString</li>")) {
			if($FirstOnly) {
				Set-Location $folder.FullName
				return
			}
			Write-Host $folder.Name
		}
	}
}

# Scans all mods for Manifests containing logic for load-order. Since vanilla added this its no longer needed.
function Get-WrongManifest {
	$allMods = Get-ChildItem -Directory $localModFolder
	foreach($folder in $allMods) {
		if(-not (Test-Path "$($folder.FullName)\About\Manifest.xml")) {
			continue
		}
		$manifestFile = "$($folder.FullName)\About\Manifest.xml"
		if((Get-Content -path $manifestFile -Raw -Encoding UTF8).Contains("<li>")) {
			explorer.exe $manifestFile
			Set-Location $folder.FullName
			return
		}
	}
}

# Simple update-notification for Discord
function Push-UpdateNotification {
	param([switch]$Test, [string]$Changenote)
	$currentDirectory = (Get-Location).Path
	if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
		Write-Host "Can only be run from somewhere under $localModFolder, exiting"
		return			
	}
	$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	$modFolder = "$localModFolder\$modName"
	$aboutFile = "$modFolder\About\About.xml"
	$aboutContent = Get-Content $aboutFile -Raw -Encoding UTF8
	$modFileId = "$modFolder\About\PublishedFileId.txt"
	$modId = Get-Content $modFileId -Raw -Encoding UTF8
	$modFullName = ($aboutContent.Replace("<name>", "|").Split("|")[1].Split("<")[0])
	$modUrl = "https://steamcommunity.com/sharedfiles/filedetails/?id=$modId"

	if($Changenote.Length -gt 0) {
		$discordHookUrl = $discordUpdateHookUrl
		$content = (Get-Content $discordUpdateMessage -Raw -Encoding UTF8).Replace("[modname]", $modFullName).Replace("[modurl]", $modUrl).Replace("[changenote]", $Changenote)
	} else {
		$discordHookUrl = $discordPublishHookUrl
		$content = (Get-Content $discordPublishMessage -Raw -Encoding UTF8).Replace("[modname]", $modFullName).Replace("[modurl]", $modUrl)
	}
	
	if($Test) {
		Write-Host "Would have posted the following message to Discord-channel:`n$content"
	} else {
		$payload = [PSCustomObject]@{
			content = $content
			username = "Update Bot"
		}
		try {
			Invoke-RestMethod -Uri $discordHookUrl -Method Post -Headers @{ "Content-Type" = "application/json" } -Body ($payload | ConvertTo-Json) | Out-Null
			Write-Host "Message posted to Discord"
		} catch {
			Write-Host "Failed to post message to Discord"
		}
	}
}

# Helper function
# Generates default language files for english
function Set-Translation {
	param (
		[string] $ModName
	)
	$rimTransExe = $settings.rimtrans_path
	$currentFile = $rimTransTemplate.Replace(".xml", "_current.xml")
	$command = "-p:$currentFile"

	Write-Host "Generating default language-data"

	(Get-Content $rimTransTemplate -Raw -Encoding UTF8).Replace("[modpath]", "$localModFolder\$ModName") | Out-File $currentFile -Encoding utf8
	
	$process = Start-Process -FilePath $rimTransExe -ArgumentList $command -PassThru 
	Start-Sleep -Seconds 1
	$wshell = New-Object -ComObject wscript.shell;
	$wshell.AppActivate('RimTrans')
	$wshell.SendKeys('{ENTER}')
	while(-not $process.HasExited) { Start-Sleep -Milliseconds 200 }
	Write-Host "Generation done"	
	Remove-Item -Path $currentFile -Force
}