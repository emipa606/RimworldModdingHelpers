# First get the settings from the json-file
$settingsFilePath = "$PSScriptRoot\settings.json"
if(-not (Test-Path $settingsFilePath)) {
	Write-Host "Could not find settingsfile: $settingsFilePath, exiting."
	return
}
$Global:settings = Get-Content -Path $settingsFilePath -raw -Encoding UTF8 | ConvertFrom-Json
$Global:localModFolder = "$($settings.rimworld_folder_path)\Mods"
$Global:oldRimworldFolder = $settings.old_rimworld_folders
$Global:playingModsConfig = "$PSScriptRoot\ModsConfig_Playing.xml"
$Global:moddingModsConfig = "$PSScriptRoot\ModsConfig_Modding.xml"
$Global:testingModsConfig = "$PSScriptRoot\ModsConfig_Testing.xml"
$Global:autoModsConfig = "$PSScriptRoot\ModsConfig_Auto.xml"
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
if(-not (Test-Path "$($settings.mod_staging_folder)\..\modlist.json")) {
	"{}" | Out-File -Encoding utf8 -FilePath "$($settings.mod_staging_folder)\..\modlist.json"
}
$Global:modlist = Get-Content "$($settings.mod_staging_folder)\..\modlist.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$Global:identifierCache = @{}


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
	param($modName)
	if(-not $modName) {
		$currentDirectory = (Get-Location).Path
		if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
			Write-Host "Can only be run from somewhere under $localModFolder, exiting"
			return			
		}
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	}
	$modFolder = "$localModFolder\$modName"
	if(-not (Test-Path $modFolder)) {
		Write-Host "$modFolder can not be found, exiting"
		return	
	}
	if(-not (Get-OwnerIsMeStatus -modName $modName)) {
		Write-Host "$modName is not mine, aborting update"
		return
	}
	Set-Location $modfolder
	$files = Get-ChildItem . -Recurse
	foreach ($file in $files) { 
		if(-not $file.FullName.Contains("Textures")){
			continue
		}
		if($file.Extension -eq ".psd") {
			Move-Item $file.FullName "$localModFolder\$modName\Source\" -Force -Confirm:$false | Out-Null
			continue
		}
		$newName = $file.Name.Replace("_side", "_east").Replace("_Side", "_east").Replace("_front", "_south").Replace("_Front", "_south").Replace("_back", "_north").Replace("_Back", "_north").Replace("_rear", "_north").Replace("_Rear", "_north")
		$newPath = $file.FullName.Replace($file.Name, $newName)
		Move-Item $file.FullName "$newPath" -ErrorAction SilentlyContinue | Out-Null
	}
}

# Easy load of a mods steam-page
# Gets the published ID for a mod and then opens it in the selected browser
function Get-ModPage {
	param(
		[string]$modName,
		[switch]$getLink
	)
	if(-not $modName) {
		$currentDirectory = (Get-Location).Path
		if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
			Write-Host "Can only be run from somewhere under $localModFolder, exiting"
			return			
		}
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	}
	$modFileId = "$localModFolder\$modName\About\PublishedFileId.txt"
	if(-not (Test-Path $modFileId)) {
		Write-Host "No id found for mod at $modFileId, exiting."
		return
	}
	$modId = Get-Content $modFileId -Raw -Encoding UTF8
	$arguments = "https://steamcommunity.com/sharedfiles/filedetails/?id=$modId"
	if($getLink) {
		return $arguments
	}
	$applicationPath = $settings.browser_path
	Start-Process -FilePath $applicationPath -ArgumentList $arguments
	Start-Sleep -Seconds 1
	Remove-Item "$localModFolder\$modName\debug.log" -Force -ErrorAction SilentlyContinue
}


# Easy load of a mods git-repo
function Get-ModRepository {
	param(
		[string]$modName,
		[switch]$getLink
	)
	if(-not $modName) {
		$currentDirectory = (Get-Location).Path
		if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
			Write-Host "Can only be run from somewhere under $localModFolder, exiting"
			return			
		}
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	}
	$modNameClean = $modName.Replace("+", "Plus")
	$arguments = "https://github.com/$($settings.github_username)/$modNameClean"
	if($getLink) {
		return $arguments
	}	
	$applicationPath = $settings.browser_path
	Start-Process -FilePath $applicationPath -ArgumentList $arguments
	Start-Sleep -Seconds 1
	Remove-Item "$localModFolder\$modName\debug.log" -Force -ErrorAction SilentlyContinue
}

# Fetchs a mods subscriber-number
function Get-ModSubscribers{
	param(
		$modName,
		$modLink
	)
	if(-not $modLink) {
		if(-not $modName) {
			$currentDirectory = (Get-Location).Path
			if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
				Write-Host "Can only be run from somewhere under $localModFolder, exiting"
				return			
			}
			$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
		}
		$modFileId = "$localModFolder\$modName\About\PublishedFileId.txt"
		if(-not (Test-Path $modFileId)) {
			Write-Host "$modFileId not found, exiting"
			return
		}
		$modId = Get-Content $modFileId -Raw -Encoding UTF8
		$url = "https://steamcommunity.com/sharedfiles/filedetails/?id=$modId"
	} else {
		$url = $modLink
	}
	return Get-HtmlPageStuff -url $url -subscribers
}

# Fetchs a mods subscriber-number
function Get-ModVersions{
	param(
		$modName,
		$modLink,
		[switch] $local
	)
	if($local) {
		if(-not $modName) {
			$currentDirectory = (Get-Location).Path
			if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
				Write-Host "Can only be run from somewhere under $localModFolder, exiting"
				return			
			}
			$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
		}
		if(-not (Test-Path "$localModFolder\$modName\About\About.xml")) {
			Write-Host "No aboutfile found for $modName"
			return
		}
		$aboutContent = Get-Content "$localModFolder\$modName\About\About.xml" -Raw -Encoding UTF8
		$versionArray = $aboutContent.Replace("<supportedVersions>", "|").Split("|")[1].Replace("</supportedVersions>", "|").Split("|")[0].Replace("<li>", "|").Split("|")
		$returnArray = @()
		foreach($versionString in $versionArray) {
			$version = ($versionString.Split("<")[0]).Trim()
			if($version) {
				$returnArray += $version
			}
		}
		return $returnArray
	}

	if(-not $modLink) {
		if(-not $modName) {
			$currentDirectory = (Get-Location).Path
			if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
				Write-Host "Can only be run from somewhere under $localModFolder, exiting"
				return			
			}
			$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
		}
		$modFileId = "$localModFolder\$modName\About\PublishedFileId.txt"
		if(-not (Test-Path $modFileId)) {
			Write-Host "$modFileId not found, exiting"
			return
		}
		$modId = Get-Content $modFileId -Raw -Encoding UTF8
		$url = "https://steamcommunity.com/sharedfiles/filedetails/?id=$modId"
	} else {
		$url = $modLink
	}
	return Get-HtmlPageStuff -url $url
}

function Get-ModSteamStatus{
	[CmdletBinding()]
	param (
		$modName,
		$modLink
	)
	$currentVersionString = Get-CurrentRimworldVersion
	if($modLink){
		$modVersions  = Get-ModVersions -modLink $modLink
	}
	if($modName) {		
		$modVersions  = Get-ModVersions -modName $modName
	}
	if(-not $modVersions) {
		Write-Verbose "Can not find mod on Steam. Modname: $modName, ModLink: $modLink, exiting"
		return $false
	}

	Write-Verbose "Found mod-versions on steam: $modversions, and current game-version is $currentVersionString"
	if($modVersions -match $currentVersionString) {
		return $true
	}
	return $false
}

# Adds an update post to the mod
# If HugsLib is loaded this will be shown if new to user
function Set-ModUpdateFeatures {
	param (
		[string] $modName
	)
	if(-not (Get-OwnerIsMeStatus -modName $modName)) {
		Write-Host "$modName is not mine, aborting update"
		return
	}
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
		(Get-Content -Path $updatefeaturesTemplate -Raw -Encoding UTF8).Replace("[modname]", $modName).Replace("[modid]", $modId) | Out-File "$localModFolder\$modName\News\$updatefeaturesFileName"
	}

	$defaultNewsObject = "	<HugsLib.UpdateFeatureDef ParentName=""UpdateFeatureBase"">
		<defName>[newsid]</defName>
		<assemblyVersion>[version]</assemblyVersion>
		<content>[news]</content>
	</HugsLib.UpdateFeatureDef>
</Defs>"
	$manifestFile = "$localModFolder\$modName\About\Manifest.xml"
	$version = ((Get-Content $manifestFile -Raw -Encoding UTF8).Replace("<version>", "|").Split("|")[1].Split("<")[0])

	$newsObject = $defaultNewsObject.Replace("[newsid]", "$($modName.Replace(" ", "_"))_$($version.Replace(".", "_"))")
	$newsObject = $newsObject.Replace("[version]", $version).Replace("[news]", $news)

	(Get-Content -Path "$localModFolder\$modName\News\$updatefeaturesFileName" -Raw -Encoding UTF8).Replace("</Defs>", $newsObject) | Out-File "$localModFolder\$modName\News\$updatefeaturesFileName"
	Write-Host "Added update news"
}


# Adds an changelog post to the mod
function Set-ModChangeNote {
	param (
		[string] $modName,
		[string] $Changenote
	)	
	if(-not (Get-OwnerIsMeStatus -modName $modName)) {
		Write-Host "$modName is not mine, aborting update"
		return
	}
	$baseLine = "# Changelog for $modName"
	$changelogFilePath = "$localModFolder\$modName\About\Changelog.txt"
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
			[string]$testAuthor,
			[switch]$alsoLoadBefore,
			[switch]$rimThreaded,
			[Parameter()][ValidateSet('1.0','1.1','1.2','latest')][string[]]$version,
			[switch]$autotest,
			[switch]$force,
			[switch]$bare
			)

	if($test -and $play) {
		Write-Host "You cant test and play at the same time."
		return
	}
	if(-not $oldRimworldFolder -and $version -eq "latest") {
		Write-Host "No old RimWorld-folder defined, cannot start old version."
		return		
	}
	if($version -and -not ($play -or $testMod)) {
		Write-Host "Only testing or playing is supported for old versions of RimWorld"
		return		
	}

	$prefsFile = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\Prefs.xml"
	$modFile = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\ModsConfig.xml"
	if($version -and $version -ne "latest") {
		$oldVersions = Get-ChildItem $oldRimworldFolder -Directory | Select-Object -ExpandProperty Name
		if(-not $oldVersions.Contains($version)) {
			Write-Host "No RimWorld-folder matching version $version found in $oldRimworldFolder."
			return		
		}		
		$prefsFile = "$oldRimworldFolder\$version\DataFolder\Config\Prefs.xml"
		$modFile = "$oldRimworldFolder\$version\DataFolder\Config\ModsConfig.xml"
		$testModFile = "$oldRimworldFolder\ModsConfig_$version.xml"
		$oldModFolder = "$oldRimworldFolder\$version\Mods"
	} else {
		$currentActiveMods = Get-Content $modFile -Encoding UTF8
		if($currentActiveMods.Length -gt 50) {
			$currentActiveMods | Set-Content -Path $playingModsConfig -Encoding UTF8
		} else {
			$currentActiveMods | Set-Content -Path $moddingModsConfig -Encoding UTF8
		}		
	}	

	Stop-Process -Name "RimWorldWin64" -ErrorAction SilentlyContinue
	Start-Sleep -Seconds 2

	if($testAuthor) {
		Copy-Item $testingModsConfig $modFile -Confirm:$false
		if($autotest -or $bare) {
			Copy-Item $autoModsConfig $modFile -Confirm:$false
		}	
		$modsToTest = Get-AllModsFromAuthor -author $testAuthor -onlyPublished
		$modIdentifiersPrereq = ""
		$modIdentifiers = ""
		foreach($modname in $modsToTest) {
			if($alsoLoadBefore) {
				$identifiersToAdd = Get-IdentifiersFromMod -modname $modname -alsoLoadBefore
			} else {
				$identifiersToAdd = Get-IdentifiersFromMod -modname $modname			
			}
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
		if($rimThreaded) {
			Write-Host "Adding RimThreaded last"
			$modIdentifiers += "<li>majorhoff.rimthreaded</li>"
		}
		(Get-Content $modFile -Raw -Encoding UTF8).Replace("</activeMods>", "$modIdentifiersPrereq</activeMods>").Replace("</activeMods>", "$modIdentifiers</activeMods>") | Set-Content $modFile
		(Get-Content $prefsFile -Raw -Encoding UTF8).Replace("<resetModsConfigOnCrash>True</resetModsConfigOnCrash>", "<resetModsConfigOnCrash>False</resetModsConfigOnCrash>").Replace("<devMode>False</devMode>", "<devMode>True</devMode>").Replace("<screenWidth>$($settings.playing_screen_witdh)</screenWidth>", "<screenWidth>$($settings.modding_screen_witdh)</screenWidth>").Replace("<screenHeight>$($settings.playing_screen_height)</screenHeight>", "<screenHeight>$($settings.modding_screen_height)</screenHeight>").Replace("<fullscreen>True</fullscreen>", "<fullscreen>False</fullscreen>") | Set-Content $prefsFile
	}
	if($testMod) {
		if((-not $force) -and (-not (Get-OwnerIsMeStatus -modName $testMod))) {
			Write-Host "Not my mod, exiting."
			return
		}
		if($version -and $version -ne "latest") {			
			Copy-Item $testModFile $modFile -Confirm:$false
			if($version -eq "1.0") {
				$identifiersToAdd = Get-IdentifiersFromMod -modname $testMod -oldmod
			} else {
				if($alsoLoadBefore) {
					$identifiersToAdd = Get-IdentifiersFromMod -modname $modname -alsoLoadBefore
				} else {
					$identifiersToAdd = Get-IdentifiersFromMod -modname $modname			
				}
			}
			if(Test-Path "$oldModFolder\$modname") {
				Remove-Item -Path "$oldModFolder\$modname" -Recurse -Force
			}
			Copy-Item -Path "$localModFolder\$modname" -Destination "$oldModFolder\" -Confirm:$false -Recurse -Force
			if(Test-Path "$localModFolder\$modname\_PublisherPlus.xml") {
				(Get-Content "$localModFolder\$modname\_PublisherPlus.xml" -Raw -Encoding UTF8).Replace("E:\SteamLibrary\steamapps\common\RimWorld\Mods", $oldModFolder) | Set-Content "$oldModFolder\$modname\_PublisherPlus.xml" -Encoding UTF8
			}
		} else {
			Copy-Item $testingModsConfig $modFile -Confirm:$false	
			if($autotest -or $bare) {
				Copy-Item $autoModsConfig $modFile -Confirm:$false
			}	
			if($alsoLoadBefore) {
				$identifiersToAdd = Get-IdentifiersFromMod -modname $modname -alsoLoadBefore
			} else {
				$identifiersToAdd = Get-IdentifiersFromMod -modname $modname			
			}
		}
		# if($identifiersToAdd.Length -eq 0) {
		# 	Write-Host "No mod identifiers found, exiting."
		# 	return
		# }
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
		if($rimThreaded) {
			Write-Host "Adding RimThreaded last"
			$modIdentifiers += "<li>majorhoff.rimthreaded</li>"
		}
		(Get-Content $modFile -Raw -Encoding UTF8).Replace("</activeMods>", "$modIdentifiers</activeMods>") | Set-Content $modFile
		(Get-Content $prefsFile -Raw -Encoding UTF8).Replace("<resetModsConfigOnCrash>True</resetModsConfigOnCrash>", "<resetModsConfigOnCrash>False</resetModsConfigOnCrash>").Replace("<devMode>False</devMode>", "<devMode>True</devMode>").Replace("<screenWidth>$($settings.playing_screen_witdh)</screenWidth>", "<screenWidth>$($settings.modding_screen_witdh)</screenWidth>").Replace("<screenHeight>$($settings.playing_screen_height)</screenHeight>", "<screenHeight>$($settings.modding_screen_height)</screenHeight>").Replace("<fullscreen>True</fullscreen>", "<fullscreen>False</fullscreen>") | Set-Content $prefsFile
	}
	if($play) {
		if(-not $version -or $version -eq "latest") {	
			Copy-Item $playingModsConfig $modFile -Confirm:$false
		}
		(Get-Content $prefsFile -Raw -Encoding UTF8).Replace("<devMode>True</devMode>", "<devMode>False</devMode>").Replace("<screenWidth>$($settings.modding_screen_witdh)</screenWidth>", "<screenWidth>$($settings.playing_screen_witdh)</screenWidth>").Replace("<screenHeight>$($settings.modding_screen_height)</screenHeight>", "<screenHeight>$($settings.playing_screen_height)</screenHeight>").Replace("<fullscreen>False</fullscreen>", "<fullscreen>True</fullscreen>") | Set-Content $prefsFile
	}
	if(-not $testMod -and -not $play -and -not $testAuthor ) {
		Copy-Item $moddingModsConfig $modFile -Confirm:$false
		(Get-Content $prefsFile -Raw -Encoding UTF8).Replace("<resetModsConfigOnCrash>True</resetModsConfigOnCrash>", "<resetModsConfigOnCrash>False</resetModsConfigOnCrash>").Replace("<devMode>False</devMode>", "<devMode>True</devMode>").Replace("<screenWidth>$($settings.playing_screen_witdh)</screenWidth>", "<screenWidth>$($settings.modding_screen_witdh)</screenWidth>").Replace("<screenHeight>$($settings.playing_screen_height)</screenHeight>", "<screenHeight>$($settings.modding_screen_height)</screenHeight>").Replace("<fullscreen>True</fullscreen>", "<fullscreen>False</fullscreen>") | Set-Content $prefsFile
	}
	if(-not $version -or $version -eq "latest") {
		$hugsSettingsPath = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\HugsLib\ModSettings.xml"
		$hugsContent = Get-Content $hugsSettingsPath -Encoding UTF8 -Raw
		if($autotest) {
			$hugsContent.Replace("Disabled", "GenerateMap") | Out-File $hugsSettingsPath -Encoding utf8
		} else {
			$hugsContent.Replace("GenerateMap", "Disabled") | Out-File $hugsSettingsPath -Encoding utf8
		}
	}

	Start-Sleep -Seconds 2
	$currentLocation = Get-Location
	if($version -and $version -ne "latest") {	
		$applicationPath = "$oldRimworldFolder\$version\RimWorldWin64.exe"
		$arguments = "-savedatafolder=DataFolder"
		Set-Location "$oldRimworldFolder\$version"
	} else {
		$applicationPath = $settings.steam_path
		$arguments = "-applaunch 294100"
	}
	$startTime = Get-Date
	Start-Process -FilePath $applicationPath -ArgumentList $arguments
	if($currentLocation -ne (Get-Location)) {
		Set-Location $currentLocation
	}
	if(-not $autotest) {
		return $true
	}
	$logPath = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Player.log"
	while ((Get-Item -Path $logPath).LastWriteTime -ge (Get-Date).AddSeconds(-15) -or (Get-Item -Path $logPath).LastWriteTime -lt $startTime) {
		Start-Sleep -Seconds 1
	}
	Stop-Process -Name "RimWorldWin64" -ErrorAction SilentlyContinue
	$errors = (Get-Content $logPath -Raw -Encoding UTF8).Contains("[HugsLib][ERR]")
	if($errors) {
		Copy-Item $logPath "$localModFolder\$modname\Source\lastrun.log" -Force | Out-Null
	}
	return (-not $errors)
}

function Set-CorrectFolderStructure {
	param($modName)
	if(-not $modName) {
		$currentDirectory = (Get-Location).Path
		if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
			Write-Host "Can only be run from somewhere under $localModFolder, exiting"
			return			
		}
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	}
	if(-not (Get-OwnerIsMeStatus -modName $modName)) {
		Write-Host "$modName is not mine, aborting update"
		return
	}
	$modFolder = "$localModFolder\$modName"
	$aboutFile = "$modFolder\About\About.xml"
	if(-not (Test-Path $aboutFile)) {
		Write-Host -ForegroundColor Yellow "No about-file for $modName"
		return
	}
	if(-not (Test-Path "$modFolder\About\PublishedFileId.txt")) {
		Write-Host -ForegroundColor Yellow "$modName is not published"
		return
	}
	if(Test-Path "$modFolder\LoadFolders.xml") {
		Write-Host -ForegroundColor Yellow "$modName has a LoadFolder.xml, will not change folders"
		return
	}
	$currentVersionsString = (((Get-Content $aboutFile -Raw -Encoding UTF8) -split "<supportedVersions>")[1] -split "</supportedVersions>")[0]
	$currentVersions = $currentVersionsString -split "<li>" | ForEach-Object { if(($_ -split "<")[0].Trim().Length -gt 1) { ($_ -split "<")[0]}  }
	$missingVersionFolders = @()
	$subfolderNames = @()
	foreach	($version in $currentVersions) {
		if(Test-Path "$modFolder\$version") {
			$childFolders = Get-ChildItem "$modFolder\$version" -Directory
			foreach($folder in $childFolders) {
				if($subfolderNames.Contains($folder.Name)) {
					continue
				}
				$subfolderNames += $folder.Name
			}
		} else {			
			$missingVersionFolders += $version
		}
	}
	if($missingVersionFolders.Length -eq 0 -or $missingVersionFolders.Length -eq $currentVersions.Length) {
		Write-Host -ForegroundColor Green "$modName has correct folder structure"
		return
	}
	if($missingVersionFolders.Length -gt 1) {
		Write-Host -ForegroundColor Yellow "$modName has $($missingVersionFolders.Length) missing version-folders, cannot fix automatically"
		return	
	}
	Write-Host "$modName has missing version-folder: $($missingVersionFolders -join ",")"
	Write-Host "Will move the following folders to missing version-folder: $($subfolderNames -join ",")"
	foreach($missingVersionFolder in $missingVersionFolders) {
		New-Item -Path "$modFolder\$missingVersionFolder" -ItemType Directory -Force | Out-Null
		foreach($subfolderName in $subfolderNames) {
			if(Test-Path "$modFolder\$subfolderName") {
				Move-Item -Path "$modFolder\$subfolderName" -Destination "$modFolder\$missingVersionFolder\$subfolderName" -Force | Out-Null
			} else {
				Write-Host "$modFolder\$subfolderName doeas not exist, version-specific folder"
			}
		}
	}
	Write-Host -ForegroundColor Green "$modName has correct folder structure"
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
	param ([string]$modname, 
		   [switch]$oldmod, 
		   [switch]$alsoLoadBefore,
		   [string]$modFolderPath)
	if($modFolderPath) {		
		$aboutFile = "$modFolderPath\About\About.xml"
	} else {
		$aboutFile = "$localModFolder\$modname\About\About.xml"		
	}
	if(-not (Test-Path $aboutFile)) {
		Write-Host "Could not find About-file for mod named $modname"
		return @()
	}
	$aboutFileContent = Get-Content $aboutFile -Raw -Encoding UTF8
	$identifiersList = $aboutFileContent.Replace("<packageId>", "|").Split("|")
	$identifiersToAdd = @()
	if($oldmod) {
		$identifiersToAdd += $modName
		return $identifiersToAdd
	}
	$identifiersToIgnore = "brrainz.harmony", "unlimitedhugs.hugslib", "ludeon.rimworld", "ludeon.rimworld.royalty", "mlie.showmeyourhands"
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
	if($alsoLoadBefore -and $aboutFileContent.Contains("<loadAfter>")){
		$identifiersList = $aboutFileContent.Replace("<loadAfter>", "|").Split("|")[1].Replace("</loadAfter>", "|").Split("|")[0].Replace("<li>", "|").Split("|")
		foreach($identifier in $identifiersList) {
			$identifierString = $identifier.Split("<")[0].ToLower()
			if(-not ($identifierString.Contains(".")) -or $identifiersToIgnore.Contains($identifierString) -or $identifierString.Contains(" ")) {
				continue
			}
			if(-not $identifiersToAdd.Contains($identifierString)) {
				$identifiersToAdd += $identifierString
			}
		}
	}
	if($identifiersToAdd.Count -gt 1) {
		$mainIdentifier = $identifiersToAdd[0]
		$oldList = $identifiersToAdd
		$identifiersToAdd = @()
		$oldList | ForEach-Object { if($_ -ne $mainIdentifier) { $identifiersToAdd += $_}}
		$identifiersToAdd += $mainIdentifier 
	}
	#[array]::Reverse($identifiersToAdd)
	return $identifiersToAdd
}

function Update-Mods {
	param([switch]$NoVs,
		[switch]$NoDependencies,
		[switch]$ConfirmContinue,
		[int]$MaxToUpdate = 5)
	$currentVersion = Get-CurrentRimworldVersion
	for ($i = 0; $i -lt $MaxToUpdate; $i++) {
		if(-not (Get-NotUpdatedMods -NoVs:$NoVs -NoDependencies:$NoDependencies -FirstOnly)) {
			Write-Host "Found no mods to update"
			Set-Location $localModFolder
			return
		}
		$currentDirectory = (Get-Location).Path
		if(-not (Test-Path "$currentDirectory\Source")) {
			New-Item -ItemType Directory -Name "Source" | Out-Null
		}
		$logFile = "$currentDirectory\Source\autoupdate.log"
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
		Write-Host "Starting update of $modName"
		Get-Date -Format "yyyy-MM-dd HH:mm:ss" | Set-Content $logFile -Encoding utf8
		"Starting autoupdate to version $currentVersion" | Add-Content $logFile -Encoding utf8
		"Updating folder-structure" | Add-Content $logFile -Encoding utf8
		Update-ModStructure -ForNewVersion | Add-Content $logFile -Encoding utf8
		"Updating VSCode if needed" | Add-Content $logFile -Encoding utf8
		$result = Update-VSCodeLoop -modName $modName
		if($result) {
			"True" | Add-Content $logFile -Encoding utf8
		} else {
			"Gave up updating the mod, moving to next." | Add-Content $logFile -Encoding utf8
			New-Item -Path "$currentDirectory\Source\lastrun.log" -ItemType File -ErrorAction SilentlyContinue | Out-Null
			continue
		}
		"Testing mod" | Add-Content $logFile -Encoding utf8
		$result = Test-Mod -autotest
		if(-not $result) {
			"Mod threw errors, aborting autotest, see Source\lastrun.log for info" | Add-Content $logFile -Encoding utf8
			continue
		}
		"Mod passed autotest, publishing" | Add-Content $logFile -Encoding utf8
		Publish-Mod -ChangeNote "Mod updated for $currentVersion and passed autotests"
		if($ConfirmContinue) {
			Read-Host "Continue?"
		}
	}	
}

function Update-VSCodeLoop {
	[CmdletBinding()]
	param($modName)
	if(-not $modName) {
		$currentDirectory = (Get-Location).Path
		if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
			Write-Host "Can only be run from somewhere under $localModFolder, exiting"
			return $false		
		}
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	}
	$cscprojFiles = Get-ChildItem -Recurse -Path $modFolder -Include *.csproj
	if(-not $cscprojFiles) {
		return $true
	}

	Start-VSProject -modname $modName
	while ($true) {
		$answer = Read-Host "Enter for testing mod, Y+Enter for accepting, N+Enter for aborting"
		if($answer.ToLower() -eq "y") {
			return $true
		}
		if($answer.ToLower() -eq "n") {
			return $false
		}
		Test-Mod -bare
	}
	return $false
}

# Checks for updated versions of updated mods
function Update-ModsStatistics {
	[CmdletBinding()]
	param([switch]$localOnly)
	$allMods = Get-ChildItem -Directory $localModFolder
	$templateModObject = @"
{
	"Name":  "",
	"Subscribers":  0,
	"Archived":  false,
	"Steamlink": "",
	"Githublink": "",
	"ID": 0,
	"Selfmade": true,
	"Version": "0.0",
	"LastUpdated": ""
}
"@	
	$i = 0
	$total = $allMods.Count
	Write-Host "`n`n`n`n`n`n"

	foreach($folder in $allMods) {
		$i++
		$percent =  [math]::Round($i / $total * 100)
		$modName = $folder.Name
		Write-Progress -Activity "Updating $($modName)" -Status "$i of $total" -PercentComplete $percent;
		$modFileId = "$($folder.FullName)\About\PublishedFileId.txt"
		if(-not (Test-Path $modFileId)) {
			Write-Verbose "$modName not published, skipping"
			continue
		}
		$aboutFile = "$($folder.FullName)\About\About.xml"		
		$aboutContent = Get-Content $aboutFile -Raw -Encoding UTF8
		if(-not (Get-OwnerIsMeStatus -modName $modName)) {
			Write-Verbose "$modName is not created by me, skipping"
			$modlist.PSObject.Properties.Remove($modName)
			continue
		}
		if(-not $modlist.$modName) {
			$modlist | Add-Member -MemberType NoteProperty -Name "$modName" -Value $(ConvertFrom-Json $templateModObject)
			$modlist.$modName.Name = "$($aboutContent.Replace("<name>", "|").Split("|")[1].Split("<")[0])"
		}
		$manifestFile = "$($folder.FullName)\About\Manifest.xml"
		$steamLink = Get-ModPage -modName $modName -getLink
		$githubLink = Get-ModRepository -modName $modName -getLink
		$modlist.$modName.Steamlink = $steamLink
		$modlist.$modName.Githublink = $githubLink
		if(-not $localOnly) {
			$modlist.$modName.Subscribers = Get-ModSubscribers -modLink $steamLink		
		}
		$modlist.$modName.ID = Get-Content $modFileId -Raw -Encoding UTF8
		if(Test-Path $manifestFile) {
			$modlist.$modName.Version = ((Get-Content $manifestFile -Raw -Encoding UTF8).Replace("<version>", "|").Split("|")[1].Split("<")[0])
			$modlist.$modName.LastUpdated = Get-Date (Get-Item $manifestFile).LastWriteTime -Format "yyyy-MM-dd HH:mm:ss"
		}
		if($modlist.$modName.Name -match "Continued" -or $aboutContent -match "Update of" -or $aboutContent -notmatch "<author>Mlie</author>") {
			$modlist.$modName.Selfmade = $false				
			if(-not $localOnly) {
				$description = ($aboutContent.Replace("<description>", "|").Split("|")[1].Split("<")[0])
				[regex]$regex = 'https:\/\/steamcommunity\.com\/sharedfiles\/filedetails\/\?id=[0-9]+\s'
				$originalLink = $regex.Matches($description).Value
				if($originalLink.Count -gt 1) {
					$originalLink = $originalLink[0]
				}
				if($originalLink) {
					Write-Verbose "Testing status for original: $originalLink"
					if(Get-ModSteamStatus -modLink $originalLink) {
						Write-Host "$modName might no longer be needed, original link is latest version."
						# Get-ModRepository -modName $modName
						# Get-ModPage -modName $modName
						# $modlist.$modName.Archived = $true
					}
				}
			}
		}
	}
	foreach($modName in ($modlist.PSObject.Properties).Name) {
		if(($allMods.Name).Contains($modName)) {
			continue
		}
		Write-Verbose "$($modName) not found, removing"
		$modlist.PSObject.Properties.Remove($modName)
	}
	$modlist | ConvertTo-Json | Set-Content "$($settings.mod_staging_folder)\..\modlist.json" -Encoding UTF8
}

function Update-ModPreviewImage {
	[CmdletBinding()]
	param($modName)
	if(-not $modName) {
		$currentDirectory = (Get-Location).Path
		if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
			Write-Host "Can only be run from somewhere under $localModFolder, exiting"
			return			
		}
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	}
	if(-not (Get-OwnerIsMeStatus -modName $modName)) {
		Write-Host "$modName is not mine, aborting update"
		return
	}
	$modFolder = "$localModFolder\$modName"
	$modIdFile = "$($modFolder)\About\PublishedFileId.txt"
	if(-not (Test-Path $modIdFile)) {
		Write-Host "$modIdFile does not exist"
		return
	}
	$aboutFile = "$modFolder\About\About.xml"
	$aboutContent = Get-Content $aboutFile -Raw -Encoding UTF8
	$description = (($aboutContent -split "<description>")[1] -split "</description>")[0]
	$previewFile = "$($modFolder)\About\Preview.png"
	if(-not (Test-Path $previewFile) -or (Get-Item $previewFile).LastWriteTime -gt (Get-Date -Date "2020-09-12")) {
		Write-Host "Preview-image does not exist or has already been updated."
		return
	}
	Write-Verbose "Found $previewFile and it has not been updated since design-change"
	if($description -match "https://steamcommunity.com/sharedfiles/filedetails") {
		$previousModId = (($description -split "https://steamcommunity.com/sharedfiles/filedetails/\?id=")[1] -split "[^0-9]")[0]
	} else {		
		Write-Host "$modName is not a continuation or the original in not on steam."
		return
	}

	$imageUrl = Get-HtmlPageStuff -url "https://steamcommunity.com/sharedfiles/filedetails/?id=$previousModId" -previewUrl
	if(-not $imageUrl) {
		"No previous image found for $modName"
		return
	}
	if(-not (Test-Path "$($modFolder)\Source")) {
		New-Item -Path "$($modFolder)\Source" -ItemType Directory | Out-Null
	}
	Write-Verbose "Fetching image from $imageUrl"
	$imagePath = "$($modFolder)\Source\original_preview.png"
	Invoke-WebRequest $imageUrl -OutFile $imagePath
	
	$gimpPath = "C:\\Users\\inade\\AppData\\Local\\Programs\\GIMP 2\\bin\\gimp-2.10.exe"
	$arguments = @($imagePath)
	Start-Process -FilePath $gimpPath -ArgumentList $arguments -NoNewWindow
	Read-Host "Waitning for image to be updated"
}

function Update-ModDescriptionFromPreviousMod {
	param($modName,
		[switch]$localSearch,
		[switch]$noConfimation)
	if(-not $modName) {
		$currentDirectory = (Get-Location).Path
		if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
			Write-Host "Can only be run from somewhere under $localModFolder, exiting"
			return			
		}
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	}
	
	if(-not (Get-OwnerIsMeStatus -modName $modName)) {
		Write-Host "$modName is not mine, aborting update"
		return
	}
	$modFolder = "$localModFolder\$modName"
	$aboutFile = "$($modFolder)\About\About.xml"		
	$aboutContent = Get-Content $aboutFile -Raw -Encoding UTF8
	if(-not ($aboutContent -match "NOW7jU1.png\[\/img\]")) {
		Write-Host "Local description for $modName does not contain NOW7jU1.png[/img]"
		return		
	}

	$applicationPath = "E:\\ModPublishing\\SteamDescriptionEdit\\Compiled\\SteamDescriptionEdit.exe"	
	$stagingDirectory = $settings.mod_staging_folder
	$tempDescriptionFile = "$stagingDirectory\tempdesc.txt"
	if($localSearch) {
		$currentDescription = ((($aboutContent -split "<description>")[1]) -split "</description>")[0]
	} else {
		$modId = Get-Content "$($modFolder)\About\PublishedFileId.txt" -Raw
		Remove-Item -Path $tempDescriptionFile -Force -ErrorAction SilentlyContinue
		$arguments = @($modId,"SAVE",$tempDescriptionFile)  
		Start-Process -FilePath $applicationPath -ArgumentList $arguments -Wait -NoNewWindow
		if(-not (Test-Path $tempDescriptionFile)) {
			Write-Host "No description found on steam for $modName"
			return			
		}
		$currentDescription = Get-Content -Path $tempDescriptionFile -Raw -Encoding UTF8
		if($currentDescription.Length -eq 0) {
			Write-Host "Description found on steam for $modName was empty"
			return		
		}
	}
	if($currentDescription -match "https://steamcommunity.com/sharedfiles/filedetails") {
		$previousModId = (($currentDescription -split "https://steamcommunity.com/sharedfiles/filedetails/\?id=")[1] -split "[^0-9]")[0]
		if(-not $previousModId) {
			Write-Host "No previous mod found for $modName, using existing instead"
			$lastPart = ($currentDescription -split "NOW7jU1.png\[\/img\]", 0)[1]
		} else {
			Remove-Item -Path $tempDescriptionFile -Force -ErrorAction SilentlyContinue
			$arguments = @($previousModId,"SAVE",$tempDescriptionFile)  
			Start-Process -FilePath $applicationPath -ArgumentList $arguments -Wait -NoNewWindow
			if(-not (Test-Path $tempDescriptionFile)) {
				Write-Host "No description found for previous mod for $modName, using id $previousModId, will keep existing"			
				$lastPart = ($currentDescription -split "NOW7jU1.png\[\/img\]")[1]
			} else {
				$lastPart = Get-Content -Path $tempDescriptionFile -Raw -Encoding UTF8
				if($lastPart.Length -eq 0) {
					Write-Host "Description found on steam for previous mod for $modName was empty, using existing instead"
					$lastPart = ($currentDescription -split "NOW7jU1.png\[\/img\]")[1]
				}
			}
		}

	} else {		
		Write-Host "Description found on steam for $modName does not contain an old mod-link on steam, will just update format"
		$lastPart = ($currentDescription -split "NOW7jU1.png\[\/img\]")[1]
	}
	$firstPart = "$(($currentDescription -split "NOW7jU1.png\[\/img\]")[0])NOW7jU1.png[/img]"
	$lastPart = $lastPart.Trim()
	$fullDescription = [Security.SecurityElement]::Escape("$firstPart`n$lastPart")

	if(-not $noConfimation) {
		Write-Verbose "First: $firstPart"
		Write-Verbose "Last: $lastPart"	
		Write-Host $fullDescription
		Write-Host -ForegroundColor Green "Continue? (CTRL+C to abort)"
		Read-Host
	}
	
	$firstFilePart = ($aboutContent -split "<description>")[0]
	$secondFilePart = ($aboutContent -split "</description>")[1]
	"$firstFilePart<description>$fullDescription</description>$secondFilePart" | Out-File $aboutFile -Encoding utf8

	if(-not $localSearch) {
		$fullDescription | Out-File $tempDescriptionFile -Encoding utf8
		$arguments = @($modId,"SET",$tempDescriptionFile)  
		Start-Process -FilePath $applicationPath -ArgumentList $arguments -Wait -NoNewWindow
		Set-Location $modFolder
		Get-ModPage
	}
}


function Update-ModDescription {
	param($searchString,
		$replaceString,
		$modName,
		[switch]$all,
		[switch]$syncBefore,
		$waittime = 500)

	if(-not $searchString) {
		Write-Host "Searchstring must be defined"
		return	
	}
	if(-not $replaceString) {
		$result = Read-Host "Replacestring is not defined, continue? (y/n)"
		if($result -eq "y") {
			return
		}	
	}
	$modFolders = @()
	if(-not $all) {
		if(-not $modName) {
			$currentDirectory = (Get-Location).Path
			if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
				Write-Host "Can only be run from somewhere under $localModFolder, exiting"
				return			
			}
			$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
		}

		$modFolder = "$localModFolder\$modName"
		if(-not (Test-Path $modFolder)) {
			Write-Host "$modFolder can not be found, exiting"
			return	
		}
		$modFolders += $modFolder
	} else {
		(Get-ChildItem -Directory $localModFolder).FullName | ForEach-Object { $modFolders += $_ }
	}
	
	Write-Host "Will replace $searchString with $replaceString in $($modFolders.Count) mods" 
	
	$applicationPath = "E:\\ModPublishing\\SteamDescriptionEdit\\Compiled\\SteamDescriptionEdit.exe"
	foreach($folder in ($modFolders | Get-Random -Count $modFolders.Count)) {	
		Start-Sleep -Milliseconds $waittime
		if(-not (Test-Path "$($folder)\About\PublishedFileId.txt")) {
			continue
		}		
		if(-not (Get-OwnerIsMeStatus -modName $(Split-Path $folder -Leaf))) {
			Write-Host "$(Split-Path $folder -Leaf) is not mine, aborting sync"
			continue
		}
		if($syncBefore) {			
			Sync-ModDescriptionFromSteam -modName $(Split-Path $folder -Leaf)
		}	
		$modId = Get-Content "$($folder)\About\PublishedFileId.txt" -Raw
		$aboutFile = "$($folder)\About\About.xml"
		$aboutContent = Get-Content $aboutFile -Raw -Encoding UTF8
		$description = "$($aboutContent.Replace("<description>", "|").Split("|")[1].Split("<")[0])"
		if(Select-String -InputObject $description -pattern $replaceString) {
			Write-Host "Description for $(Split-Path $folder -Leaf) already contains the replace-string, skipping"
			continue
		}
		if(Select-String -InputObject $description -pattern $searchString) {
			$arguments = @($modId,"REPLACE",$searchString,$replaceString)   
			Start-Process -FilePath $applicationPath -ArgumentList $arguments -Wait -NoNewWindow
			((Get-Content -path $aboutFile -Raw -Encoding UTF8).Replace($searchString,$replaceString)) | Set-Content -Path $aboutFile -Encoding UTF8
		} else {
			Write-Host "Description for $(Split-Path $folder -Leaf) does not contain $searchString"
		}
	}
	
}

function Get-OwnerIsMeStatus {
	param($modName)
	if(-not $modName) {
		$currentDirectory = (Get-Location).Path
		if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
			Write-Host "Can only be run from somewhere under $localModFolder, exiting"
			return $false	
		}
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	}

	$modFolder = "$localModFolder\$modName"
	if(-not (Test-Path $modFolder)) {
		Write-Host "$modFolder can not be found, exiting"
		return $false
	}
	$aboutFile = "$($modFolder)\About\About.xml"
	return ((Get-Content $aboutFile -Raw -Encoding UTF8).Contains("<packageId>Mlie."))
}

function Sync-ModDescriptionFromSteam {
	param($modName)
	if(-not $modName) {
		$currentDirectory = (Get-Location).Path
		if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
			Write-Host "Can only be run from somewhere under $localModFolder, exiting"
			return			
		}
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	}

	$modFolder = "$localModFolder\$modName"
	if(-not (Test-Path $modFolder)) {
		Write-Host "$modFolder can not be found, exiting"
		return	
	}
	if(-not (Get-OwnerIsMeStatus -modName $modName)) {
		Write-Host "$modName is not mine, aborting sync"
		return
	}
	if(-not (Test-Path "$($modFolder)\About\PublishedFileId.txt")) {
		Write-Host "$modName not published, aborting sync"
		return
	}	
	$modId = Get-Content "$($modFolder)\About\PublishedFileId.txt" -Raw
	$applicationPath = "E:\\ModPublishing\\SteamDescriptionEdit\\Compiled\\SteamDescriptionEdit.exe"
	$tempDescriptionFile = "$stagingDirectory\tempdesc.txt"
	Remove-Item -Path $tempDescriptionFile -Force -ErrorAction SilentlyContinue
	$arguments = @($modId,"SAVE",$tempDescriptionFile)
	Start-Process -FilePath $applicationPath -ArgumentList $arguments -Wait -NoNewWindow
	if(-not (Test-Path $tempDescriptionFile)) {
		Write-Host "No description found on steam for $modName, aborting sync"
		return
	}
	$currentDescription = Get-Content -Path $tempDescriptionFile -Raw -Encoding UTF8
	if($currentDescription.Length -eq 0) {
		Write-Host "Description found on steam for $modName was empty, aborting sync"
		return
	}
	$currentDescription = [Security.SecurityElement]::Escape($currentDescription)
	$aboutFile = "$($modFolder)\About\About.xml"
	$aboutContent = Get-Content $aboutFile -Raw -Encoding UTF8
	$description = "$($aboutContent.Replace("<description>", "|").Split("|")[1].Split("<")[0])"
	$aboutContent = $aboutContent.Replace($description, $currentDescription)
	$aboutContent | Set-Content -Path $aboutFile -Encoding UTF8
}

function Get-CleanDescription {
	param (
		$description
	)
	
}

function Sync-ModDescriptionToSteam {
	param($modName)
	if(-not $modName) {
		$currentDirectory = (Get-Location).Path
		if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
			Write-Host "Can only be run from somewhere under $localModFolder, exiting"
			return			
		}
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	}

	$modFolder = "$localModFolder\$modName"
	if(-not (Test-Path $modFolder)) {
		Write-Host "$modFolder can not be found, exiting"
		return	
	}
	if(-not (Get-OwnerIsMeStatus -modName $modName)) {
		Write-Host "$modName is not mine, aborting sync"
		return
	}
	if(-not (Test-Path "$($modFolder)\About\PublishedFileId.txt")) {
		Write-Host "$modName not published, aborting sync"
		return
	}	
	$tempDescriptionFile = "$stagingDirectory\tempdesc.txt"
	$aboutFile = "$($modFolder)\About\About.xml"
	$aboutContent = Get-Content $aboutFile -Raw -Encoding UTF8
	$description = "$($aboutContent.Replace("<description>", "|").Split("|")[1].Split("<")[0])"
	$description | Set-Content -Path $tempDescriptionFile -Encoding UTF8
	$modId = Get-Content "$($modFolder)\About\PublishedFileId.txt" -Raw
	$applicationPath = "E:\\ModPublishing\\SteamDescriptionEdit\\Compiled\\SteamDescriptionEdit.exe"
	$arguments = @($modId,"SET",$tempDescriptionFile)
	Start-Process -FilePath $applicationPath -ArgumentList $arguments -Wait -NoNewWindow
}

# Returns a list of all files that have the selected string in their XML
function Get-StringFromModFiles {
	[CmdletBinding()]
	param($searchString,
		$threads = 10,
		[switch]$firstOnly,
		$fromSave) 
	$searchStringConverted = [regex]::escape($searchString)
	if($identifierCache.Lenght -eq 0) {		
		Update-IdentifierToFolderCache
	}
	if($fromSave) {
		if(-not (Test-Path $fromSave)) {
			Write-Host -ForegroundColor Red "No save-file found from path $fromSave"
			return
		}
		[xml]$saveData = Get-Content $fromSave -Raw -Encoding UTF8
		$identifiers = $saveData.ChildNodes.meta.modIds.li
		$allMods = @()
		foreach($identifier in $identifiers) {
			if($identifierCache.Contains("$identifier")) {
				$allMods += Get-Item $identifierCache["$identifier"]
			}
		}
	} else {		
		$allMods = Get-ChildItem -Directory $localModFolder
	}
	$allMatchingFiles = @()
	$i = 0
	$total = $allMods.Count
	foreach($job in Get-Job){
		Stop-Job $job | Out-Null
		Remove-Job $job | Out-Null
	}
	foreach($folder in ($allMods | Get-Random -Count $total)) {
		$i++
		$percent = [math]::Round($i / $total * 100)
		Write-Progress -Activity "Searching $($folder.name), $($allMatchingFiles.Count) matches found" -Status "$i of $total" -PercentComplete $percent;
		while((Get-Job -State 'Running').Count -gt $threads) {
			Start-Sleep -Milliseconds 100
		}
		$ScriptBlock = {
			# 1: $folder.FullName 2: $searchStringConverted
			$foundFiles = @()
			$searchString = $args[1]
			Get-ChildItem -Path $args[0] -Recurse -File -Filter "*.xml" | ForEach-Object { if((Get-Content $_.FullName) -match $searchString) { $foundFiles += $_ } }
			return $foundFiles
		}
		$arguments = @("$($folder.FullName)",$searchStringConverted)
		Start-Job -Name "Find_$($folder.Name)" -ScriptBlock $ScriptBlock -ArgumentList $arguments | Out-Null
		foreach($job in Get-Job -State Completed){
			$result = Receive-Job $job
			$allMatchingFiles += $result
			Remove-Job $job | Out-Null
		}
		foreach($job in Get-Job -State Blocked){
			Write-Host -ForegroundColor Red  "$($job.Name) failed to exit, stopping it."
			Stop-Job $job | Out-Null
			Remove-Job $job | Out-Null
		}
		if($firstOnly -and $allMatchingFiles.Count -gt 0){
			break
		}
	}
	foreach($job in Get-Job -State Completed){
		$result = Receive-Job $job
		$allMatchingFiles += $result
		Remove-Job $job | Out-Null
	}
	foreach($job in Get-Job -State Blocked){
		Write-Host -ForegroundColor Red  "$($job.Name) failed to exit, stopping it."
		Stop-Job $job | Out-Null
		Remove-Job $job | Out-Null
	}
	if($firstOnly -and $allMatchingFiles.Count -gt 0){
		$number = ((Get-Content $allMatchingFiles[0].FullName | select-string $searchStringConverted).LineNumber)[0]
		$applicationPath = $settings.text_editor_path
		$arguments = """$($allMatchingFiles[0].FullName)""","-n$number"
		Start-Process -FilePath $applicationPath -ArgumentList $arguments
		return $allMatchingFiles[0]
	}
	return $allMatchingFiles
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

# Merges a repository with another, preserving history
function Merge-GitRepositories {
	$currentDirectory = (Get-Location).Path
	if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
		Write-Host "Can only be run from somewhere under $localModFolder, exiting"
		return			
	}
	$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	
	if(-not (Get-OwnerIsMeStatus -modName $modName)) {
		Write-Host "$modName is not mine, aborting merge"
		return
	}
	$modFolder = "$localModFolder\$modName"
	$manifestFile = "$modFolder\About\Manifest.xml"
	$stagingDirectory = $settings.mod_staging_folder
	$rootFolder = Split-Path $stagingDirectory
	$version = [version]((Get-Content $manifestFile -Raw -Encoding UTF8).Replace("<version>", "|").Split("|")[1].Split("<")[0])
	$newVersion = "$($version.Major).$($version.Minor).$($version.Build)"

	Set-Location -Path $rootFolder
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse
	Set-Location -Path $stagingDirectory

	$modNameNew = $modName.Replace("+", "Plus")
	$modNameOld = "$($modNameNew)_Old"
	if(-not (Get-RepositoryStatus -repositoryName $modNameNew)){
		Write-Host "No repository found for $modNameNew"
		Set-Location $currentDirectory
		return			
	}
	if(-not (Get-RepositoryStatus -repositoryName $modNameOld)){
		Write-Host "No repository found for $modNameOld"
		Set-Location $currentDirectory
		return			
	}

	git clone https://github.com/$($settings.github_username)/$modNameNew
	git clone https://github.com/$($settings.github_username)/$modNameOld


	Set-Location -Path $stagingDirectory\$modNameNew
	$newBranch = ((cmd.exe /c git branch) | Out-String).Split(" ")[1].Split("`r")[0]

	Set-Location -Path $stagingDirectory\$modNameOld
	$oldBranch = ((cmd.exe /c git branch) | Out-String).Split(" ")[1].Split("`r")[0]

	git checkout $oldBranch
	git fetch --tags
	git branch -m master-holder
	git remote rm origin
	git remote add origin https://github.com/$($settings.github_username)/$modNameNew
	git fetch
	git checkout $newBranch
	git pull origin $newBranch
	git rm -rf *
	git commit -m "Deleted obsolete files"
	git merge master-holder --allow-unrelated-histories
	git push origin $newBranch
	git push --tags
	
	$applicationPath = $settings.browser_path
	$arguments = "https://github.com/$($settings.github_username)/$modNameNew/tags"
	Start-Process -FilePath $applicationPath -ArgumentList $arguments
	Get-ZipFile -modname $modName -filename "$($modNameNew)_$newVersion.zip"
	Move-Item "$localModFolder\$modname\$($modNameNew)_$newVersion.zip" "$stagingDirectory\$($modNameNew)_$newVersion.zip"
	Remove-Item .\debug.log -Force -ErrorAction SilentlyContinue
	Read-Host "Waiting for zip to be uploaded from $stagingDirectory, continue when done (Press ENTER)"
	Remove-Item "$stagingDirectory\$($modNameNew)_$newVersion.zip" -Force

	Set-Location $currentDirectory
}

function Get-NextModDependancy {
	param($modId,
		$modName,
		[switch]$alsoBefore,
		[switch]$test)
	if(-not $modName) {
		$currentDirectory = (Get-Location).Path
		if(-not $currentDirectory.StartsWith($localModFolder)) {
			Write-Host "Can only be run from somewhere under $localModFolder, exiting"
			return			
		}
		if($currentDirectory -ne $localModFolder) {
			$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
		}
	}
	if($modName) {
		$folders = Get-ChildItem $localModFolder -Directory | Where-Object {$_.Name -gt $modname}
	} else {
		$folders = Get-ChildItem $localModFolder -Directory
	}
	foreach ($folder in $folders) {
		$identifiers = Get-IdentifiersFromMod -modname $folder.Name -alsoLoadBefore:$alsoBefore
		if($identifiers.Contains($modId.ToLower())) {
			Set-Location $folder.FullName
			Write-Host "Found $modId in mod $($folder.Name)"
			if($test) {
				Test-Mod
			}
			return
		}
	}
	Write-Host "$modId not found."
}

# XML-cleaning function
# Resaves all XML-files using validated XML. Also warns if there seems to be overwritten base-defs
# Useful to run on a mod to remove all extra whitespaces and redundant formatting
function Set-ModXml {
	param([switch]$skipBaseCheck,
		$modName)
	if(-not $modName) {
		$currentDirectory = (Get-Location).Path
		if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
			Write-Host "Can only be run from somewhere under $localModFolder, exiting"
			return			
		}
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	}	
	$modFolder = "$localModFolder\$modName"
	
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
			continue
		}
		if($skipBaseCheck) {
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
		[switch]$SelectFolder,
		[switch]$SkipNotifications,
		[switch]$GithubOnly,
		[string]$ChangeNote
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
	if(-not (Get-OwnerIsMeStatus -modName $modName)) {
		Write-Host "$modName is not mine, aborting publish"
		return
	}

	$modNameClean = $modName.Replace("+", "Plus")
	$stagingDirectory = $settings.mod_staging_folder
	$rootFolder = Split-Path $stagingDirectory
	$manifestFile = "$modFolder\About\Manifest.xml"
	$modsyncFile = "$modFolder\About\ModSync.xml"
	$aboutFile = "$modFolder\About\About.xml"
	$readmeFile = "$modFolder\README.md"
	$previewFile = "$modFolder\About\Preview.png"
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

	if(-not (Test-Path $previewFile)) {
		Read-Host "Preview-file does not exist, create one then press Enter"
	}
	if((Get-Item $previewFile).Length -ge 1MB) {
		Read-Host "Preview-file is too large, resave a file under 1MB and then press Enter"
	}
	if((Get-Item $previewFile).LastWriteTime -lt (Get-Date -Date "2020-09-12")) {
		Read-Host "Preview-file has not been updated since we changed logo, update first, then press Enter"
	}

	# Remove leftover-files
	if(Test-Path "$modFolder\Source\lastrun.log") {
		Remove-Item "$modFolder\Source\lastrun.log" -Force
	}

	# Generate english-language if missing
	# Set-Translation -ModName $modName

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
		((Get-Content -path $manifestFile -Raw -Encoding UTF8).Replace("[modname]",$modNameClean).Replace("[username]",$settings.github_username)) | Set-Content -Path $manifestFile -Encoding UTF8
	} else {
		$manifestContent = Get-Content -path $manifestFile -Raw -Encoding UTF8
		$currentIdentifier = $manifestContent.Replace("<identifier>", "|").Split("|")[1].Split("<")[0]
		if($currentIdentifier -ne $modNameClean) {
			((Get-Content -path $manifestFile -Raw -Encoding UTF8).Replace($currentIdentifier,$modNameClean)) | Set-Content -Path $manifestFile -Encoding UTF8
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

	$firstPublish = (-not (Test-Path "$modFolder\About\PublishedFileId.txt"))
	# Create repo if does not exists
	if(Get-RepositoryStatus -repositoryName $modNameClean) {
		if($ChangeNote) {
			$message = $ChangeNote
		} else {
			$message = Read-Host "Commit-Message"
		}
		$oldVersion = "$($version.Major).$($version.Minor).$($version.Build)"
		$newVersion = "$($version.Major).$($version.Minor).$($version.Build + 1)"
		((Get-Content -path $manifestFile -Raw -Encoding UTF8).Replace($oldVersion,$newVersion)) | Set-Content -Path $manifestFile
		((Get-Content -path $modsyncFile -Raw -Encoding UTF8).Replace($oldVersion,$newVersion)) | Set-Content -Path $modsyncFile
		if(-not $ChangeNote) {
			Set-ModUpdateFeatures -ModName $modNameClean
		}
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
	if($firstPublish){		
		Update-ModDescriptionFromPreviousMod -noConfimation -localSearch -modName $modName
	}
	else {
		Sync-ModDescriptionFromSteam -modName $modName
	}
	$aboutContent = Get-Content $aboutFile -Raw -Encoding UTF8
	if(-not $aboutContent.Contains("Rs6T6cr")) {
		$faqText = @"


[img]https://i.imgur.com/Rs6T6cr.png[/img]
[list]
[*] See if the the error persists if you just have this mod and its requirements active.
[*] If not, try adding your other mods until it happens again.
[*] Post your error-log using [url=https://steamcommunity.com/workshop/filedetails/?id=818773962]HugsLib[/url] and command Ctrl+F12
[*] For best support, please use the Discord-channel for error-reporting.
[*] Do not report errors by making a discussion-thread, I get no notification of that.
[*] If you have the solution for a problem, please post it to the GitHub repository.
[/list]
</description>
"@
		$aboutContent = $aboutContent.Replace("</description>", $faqText)
		$aboutContent | Set-Content $aboutFile -Encoding UTF8
		if(-not $firstPublish) {
			Sync-ModDescriptionToSteam -modName $modName
		}
	}

	# Clone current repository to staging
	git clone https://github.com/$($settings.github_username)/$modNameClean

	# Copy replace modfiles
	"# $modNameClean`n`r" > $readmeFile
	(Convert-BBCodeToGithub -textToConvert ((Get-Content $aboutFile -Raw -Encoding UTF8).Replace("<description>", "|").Split("|")[1].Split("<")[0])) >> $readmeFile
	robocopy $modFolder $stagingDirectory\$modNameClean /MIR /w:10 /XD .git /NFL /NDL /NJH /NJS /NP
	Set-Location -Path $stagingDirectory\$modNameClean

	# Reapply gitignore-file if necessary
	if($reapplyGitignore) {
		git rm -r --cached .
	}

	git add .
	git commit -m $message
	git push origin
	git tag -a $newVersion -m $message
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
	if($GithubOnly) {
		Write-Host "Published $modName to github only!"
		return
	}
	Start-SteamPublish -modFolder $modFolder

	if(-not $SkipNotifications -and (Test-Path "$modFolder\About\PublishedFileId.txt")) {
		if($firstPublish) {
			Push-UpdateNotification
			Get-ModPage
			$aboutContent = Get-Content $aboutFile -Raw -Encoding UTF8
			$currentDescription = ((($aboutContent -split "<description>")[1]) -split "</description>")[0]
			if($currentDescription -match "https://steamcommunity.com/sharedfiles/filedetails") {
				$previousModId = (($currentDescription -split "https://steamcommunity.com/sharedfiles/filedetails/\?id=")[1] -split "[^0-9]")[0]
				$trelloCard = Find-TrelloCardByLink -url "https://steamcommunity.com/sharedfiles/filedetails/?id=$previousModId"
				if($trelloCard) {
					Move-TrelloCardToDone -cardId $trelloCard.id
				}
			}
		} else {
			Push-UpdateNotification -Changenote "$version - $message"
		}
	}
	Write-Host "Published $modName!"
}

function Start-SteamPublish {
	param($modFolder)

	if(-not (Test-Path $modFolder)) {
		Write-Host "$modfolder does not exist"
		return
	}
	if(-not (Get-OwnerIsMeStatus -modName $(Split-Path $modfolder -Leaf))) {
		Write-Host "$(Split-Path $modfolder -Leaf) is not mine, aborting update"
		return
	}
	$copyPublishedFileId = $false
	if(!(Test-Path "$modFolder\About\PublishedFileId.txt")) {
		$copyPublishedFileId = $true
	}
	$stagingDirectory = $settings.mod_staging_folder
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse

	Write-Host "Copying mod-files to publish-dir"
	$exclusions = @()
	$exclusionFile = "$modfolder\_PublisherPlus.xml"
	if((Test-Path $exclusionFile)) {
		$splittedContent = (Get-Content $exclusionFile -Raw -Encoding UTF8).Replace("<exclude>", "|").Split("|")
		for ($i = 1; $i -lt $splittedContent.Count; $i++) {
			$exclusion = $splittedContent[$i].Replace("</exclude>", "|").Split("|")[0].Replace("$modFolder\", "")
			$exclusions += $exclusion
		}
		$exclusions += $exclusionFile.Replace("$modFolder\", "")
	}
	Copy-Item -Path "$modFolder\*" -Destination $stagingDirectory -Recurse -Exclude $exclusions

	Write-Host "Starting steam-publish"
	$publishToolPath = "E:\\ModPublishing\\SteamUpdateTool\\Compiled\\RimworldModReleaseTool.exe"
	Start-Process -FilePath $publishToolPath -ArgumentList $stagingDirectory -Wait -NoNewWindow
	if($copyPublishedFileId -and (Test-Path "$stagingDirectory\About\PublishedFileId.txt")) {
		Copy-Item -Path "$stagingDirectory\About\PublishedFileId.txt" -Destination "$modfolder\About\PublishedFileId.txt" -Force
	}
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
			$exclusion = $splittedContent[$i].Replace("</exclude>", "|").Split("|")[0].Replace("$localModFolder\$modname\", "")
			$exclusionsToAdd += " -xr!""$exclusion"""
		}
	}
	$outFile = "$localModFolder\$modname\$filename"
	$7zipPath = $settings.zip_path
	$arguments = "a ""$outFile"" ""$localModFolder\$modname\"" -r -mx=9 -mmt=10 -bd $exclusionsToAdd "
	Start-Process -FilePath $7zipPath -ArgumentList $arguments -Wait -NoNewWindow
}

# Simple push function for git
function Push-ModContent {
	$message = Read-Host "Commit-Message"
	git add .
	git commit -m $message
	git push origin
}


# Test the mod in the current directory
function Test-Mod {
	param([Parameter()]
    [ValidateSet('1.0','1.1','1.2','latest')]
    [string[]]
	$version = "latest",
	[switch] $alsoLoadBefore,
	[switch] $rimThreaded,
	[switch] $autotest,
	[switch] $force,
	[switch] $bare)
	if(-not $version) {
		$version = "latest"
	}
	$currentDirectory = (Get-Location).Path
	if(-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
		Write-Host "Can only be run from somewhere under $localModFolder, exiting"
		return			
	}
	$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	if($autotest) {
		Write-Host "Auto-testing $modName"
	} else {
		Write-Host "Testing $modName"		
	}
	return Start-RimWorld -testMod $modName -version $version -alsoLoadBefore:$alsoLoadBefore -autotest:$autotest -force:$force -rimthreaded:$rimThreaded -bare:$bare
}


# Returns a list of mods that has not been updated to the latest version
# With switch FirstOnly the current directory is changed to the next not-updated mod root path
function Get-NotUpdatedMods {
	param([switch]$FirstOnly,
		[switch]$NextOnly,
		[switch]$NoVs,
		[switch]$NoDependencies,
		[switch]$IgnoreLastErrors,
		[switch]$NotFinished,
		[int]$MaxToFetch = -1)
	$currentVersionString = Get-CurrentRimworldVersion
	$allMods = Get-ChildItem -Directory $localModFolder
	if($MaxToFetch -eq 0) {
		$MaxToFetch = $allMods.Length
	}
	$currentFolder = (Get-Location).Path
	if($currentFolder -eq $localModFolder) {
		$NextOnly = $false
		$FirstOnly = $true
		Write-Host "Standing in root-dir, will assume FirstOnly instead of NextOnly"
	}
	$foundStart = $false
	$counter = 0
	foreach($folder in $allMods) {
		if($NextOnly -and (-not $foundStart)) {
			if($folder.FullName -eq $currentFolder) {				
				Write-Host "Will search for next mod from $currentFolder"
				$foundStart = $true
			}
			continue
		}
		if($MaxToFetch -gt 0 -and $counter -ge $MaxToFetch) {
			return $false
		}
		if(-not (Test-Path "$($folder.FullName)\About\PublishedFileId.txt")) {
			continue
		}
		if(-not (Get-OwnerIsMeStatus -modName $folder.Name)) {
			continue
		}
		if(-not $IgnoreLastErrors -and (Test-Path "$($folder.FullName)Source\lastrun.log")) {
			continue
		}
		if($NoVs) {
			$cscprojFiles = Get-ChildItem -Recurse -Path $folder.FullName -Include *.csproj
			if($cscprojFiles.Length -gt 0) {
				continue
			}
		}
		$aboutFile = "$($folder.FullName)\About\About.xml"

		if($NoDependencies -and (Get-IdentifiersFromMod -modname $folder.Name).Count -gt 1) {
			continue
		}

		if(-not $NotFinished -and (Get-Content -path $aboutFile -Raw -Encoding UTF8).Contains("<li>$currentVersionString</li>")) {
			continue
		}

		if($NotFinished) {
			if((Get-Item "$($folder.FullName)\About\Changelog.txt").LastWriteTime -ge (Get-Item $aboutFile).LastWriteTime.AddMinutes(-5)) {
				continue
			}
			if(-not (Get-Content -path $aboutFile -Raw -Encoding UTF8).Contains("<li>$currentVersionString</li>")) {
				continue
			}
		}

		if($FirstOnly -or $NextOnly) {
			Set-Location $folder.FullName
			return $true
		}
		Write-Host $folder.Name
		$counter++
	}
}


# Returns the oldest mod in the mod-directory, optional VS-only switch
function Get-OldestMod {
	param([switch]$OnlyVS)
	$allMods = Get-ChildItem -Path "$localModFolder\*\About\About.xml" | Sort-Object -Property LastWriteTime 
	foreach($aboutFile in $allMods) {
		Set-Location $aboutFile.Directory.Parent
		if(-not (Get-OwnerIsMeStatus)) {
			continue
		}
		if($OnlyVS) {
			$cscprojFiles = Get-ChildItem -Recurse -Path $aboutFile.Directory.Parent -Include *.csproj	
			if($cscprojFiles.Count -eq 0) {
				continue
			}
		}
		Write-Host "$($aboutFile.Directory.Parent.Name) was updated $($aboutFile.LastWriteTimeString)"
		break
	}
}


function Get-CurrentRimworldVersion {
	param([switch]$versionObject)
	$rimworldVersionFile = "$localModFolder\..\Version.txt"
	$currentRimworldVersion = [version]([regex]::Match((Get-Content $rimworldVersionFile -Raw -Encoding UTF8), "[0-9]+\.[0-9]+")).Value
	if($versionObject) {
		return $currentRimworldVersion
	}
	return "$($currentRimworldVersion.Major).$($currentRimworldVersion.Minor)"
}


function Get-LastRimworldVersion {
	$currentVersion = Get-CurrentRimworldVersion -versionObject
	return "$($currentVersion.Major).$($currentVersion.Minor - 1)"
}

# Helper function to scrape page
function Get-HtmlPageStuff {
	[CmdletBinding()]
	param (
		$url,
		[switch] $previewUrl,
		[switch] $subscribers
	)
	$returnValue = ""
	Write-Verbose "Fetching $url"
	try { 
		$page = Invoke-WebRequest -Uri $url -UseBasicParsing -Verbose:$false
	} catch { 
		Write-Verbose "Could not fetch $url, trying again"
	} 
	if(-not $page) {
		try { 
			$page = Invoke-WebRequest -Uri $url -UseBasicParsing -Verbose:$false
		} catch { 
			Write-Verbose "Could not fetch $url, trying again"
		} 
	}
	if(-not $page) {
		try { 
			$page = Invoke-WebRequest -Uri $url -UseBasicParsing -Verbose:$false
		} catch { 
			Write-Host -ForegroundColor Red "Could not fetch $url"
			return $returnValue
		} 
	}
	# $page = Invoke-WebRequest -Uri $url -UseBasicParsing -Verbose:$false -ErrorAction SilentlyContinue
	if(-not $page) {
		Write-Host -ForegroundColor Red "Fetched $url but got no content"
		return $returnValue
	}
	$html = New-Object -Com "HTMLFile" -Verbose:$false
	# $HTML.IHTMLDocument2_write($page.Content)
	$encoded = [System.Text.Encoding]::Unicode.GetBytes($page.Content)
    $html.write($encoded)
	if($subscribers) {
		$tables = $html.all.tags("table")
		if($tables) {
			$cells = $tables[0].cells
			if($cells) {
				$returnValue = $cells[2].InnerText.Replace(",", "")
			}  
		}
	} elseif ($previewUrl)  {
		$img = ($html.all.tags("img") | Where-Object {$_.id -eq "previewImageMain" -or $_.id -eq "previewImage"}).src
		if($img) {
			$returnValue = "$($img.Split("?")[0])?"
		}
	} else {
		$divs = ($html.all.tags("div") | Where-Object -Property className -eq "rightDetailsBlock")
		if($divs) {
			$versions = $divs[0].InnerText.Replace(" ", "").Split(",")
			$returnValue =  $versions | Where-Object {$_ -and $_ -ne "Mod"}  
		}
	}
	
	$html.close()
	try {
		[System.Runtime.Interopservices.Marshal]::ReleaseComObject($HTML) | Out-Null	
	} catch {
		Write-Verbose "COM object could not be released.";
	}

	return $returnValue
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

function Convert-BBCodeToGithub {
	param($textToConvert)
	$textToConvert = $textToConvert.Replace("[b]", "**").Replace("[/b]", "**")
	$textToConvert = $textToConvert.Replace("[i]", "*").Replace("[/i]", "*")
	$textToConvert = $textToConvert.Replace("[h1]", "# ").Replace("[/h1]", "`n")
	$textToConvert = $textToConvert.Replace("[h2]", "## ").Replace("[/h2]", "`n")
	$textToConvert = $textToConvert.Replace("[h3]", "### ").Replace("[/h3]", "`n")
	$textToConvert = $textToConvert.Replace("[url=", "").Replace("[/url]", "")
	$textToConvert = $textToConvert.Replace("[img]", "![Image](").Replace("[/img]", ")`n")
	$textToRemove = (($textToConvert -split "\[table\]")[1] -split "\[/table\]")[0]
	$textToConvert = $textToConvert.Replace("`n[table]$textToRemove[/table]`n", "")
	$textToConvert = $textToConvert.Replace("[list]", "`n").Replace("[/list]", "`n").Replace("[*]", "- ")
	
	return $textToConvert
}

# Helper function
# Generates default language files for english
function Set-Translation {
	param (
		[string] $modName
	)
	if(-not (Get-OwnerIsMeStatus -modName $modName)) {
		Write-Host "$modName is not mine, aborting update"
		return
	}
	$rimTransExe = $settings.rimtrans_path
	$currentFile = $rimTransTemplate.Replace(".xml", "_current.xml")
	$command = "-p:$currentFile"

	Write-Host "Generating default language-data"

	(Get-Content $rimTransTemplate -Raw -Encoding UTF8).Replace("[modpath]", "$localModFolder\$modName") | Out-File $currentFile -Encoding utf8
	
	$process = Start-Process -FilePath $rimTransExe -ArgumentList $command -PassThru 
	Start-Sleep -Seconds 1
	$wshell = New-Object -ComObject wscript.shell;
	$wshell.AppActivate('RimTrans')
	$wshell.SendKeys('{ENTER}')
	while(-not $process.HasExited) { Start-Sleep -Milliseconds 200 }
	Write-Host "Generation done"	
	Remove-Item -Path $currentFile -Force
}

function Update-IdentifierToFolderCache {
	# First steam-dirs
	Write-Host -ForegroundColor Gray "Caching identifiers"
	Get-ChildItem "$localModFolder\..\..\..\workshop\content\294100" -Directory | ForEach-Object {
		$continue = Test-Path "$($_.FullName)\About\About.xml"
		if(-not $continue) {			
			Write-Verbose "Ignoring $($_.Name) - No aboutfile"
		} else {
			$continue = Test-Path "$($_.FullName)\About\PublishedFileId.txt"
			if(-not $continue) {			
				Write-Verbose "Ignoring $($_.Name) - Not published"
			} else {
				[xml]$aboutContent = Get-Content -path "$($_.FullName)\About\About.xml" -Raw -Encoding UTF8
				if(-not ($aboutContent.ChildNodes[1].packageId)) {
					Write-Verbose "Ignoring $($_.Name) - No identifier"
				} else {
					$identifierCache["$($aboutContent.ChildNodes[1].packageId.ToLower())"] = $_.FullName						
				}			
			}
		}		
	}
	# Then the local mods
	Get-ChildItem $localModFolder -Directory | ForEach-Object {  		
		$continue = Test-Path "$($_.FullName)\About\About.xml"
		if(-not $continue) {			
			Write-Verbose "Ignoring $($_.Name) - No aboutfile"
		} else {
			$continue = Test-Path "$($_.FullName)\About\PublishedFileId.txt"
			if(-not $continue) {			
				Write-Verbose "Ignoring $($_.Name) - Not published"
			} else {
				[xml]$aboutContent = Get-Content -path "$($_.FullName)\About\About.xml" -Raw -Encoding UTF8
				if(-not ($aboutContent.ChildNodes[1].packageId)) {
					Write-Verbose "Ignoring $($_.Name) - No identifier"
				} else {
					$identifierCache["$($aboutContent.ChildNodes[1].packageId.ToLower())"] = $_.FullName						
				}			
			}
		}	
	}
	Write-Host -ForegroundColor Gray "Done, cached $($identifierCache.Count) mod identifiers"
}

function Show-GitOrigin {
	git remote show origin
}