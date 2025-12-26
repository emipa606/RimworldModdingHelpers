#region Utility and all global variables

# Writes messages with timestamp and color
function WriteMessage {
	param($message,
		[switch]$success,
		[switch]$progress,
		[switch]$warning,
		[switch]$failure)
	$textColor = "White"
	if ($success) {
		$textColor = "Green"
	}
	if ($progress) {
		$textColor = "DarkGray"
	}
	if ($warning) {
		$textColor = "Yellow"
	}
	if ($failure) {
		$textColor = "Red"
	}
	$dateStamp = Get-Date -Format "HH:mm:ss"
	Write-Host -ForegroundColor $textColor "[$dateStamp] - $message"
}

function SetTerminalProgress {
	[CmdletBinding()]
	param (
		[switch]$unknown,
		$progressPercent
	)

	if ($unknown) {
		Write-Host -NoNewline ("`e]9;4;3`a")
		return
	}
	if ($progressPercent) {
		$percentClamped = [Math]::Min([Math]::Max([Math]::Round($progressPercent), 0), 100)
		Write-Host -NoNewline ("`e]9;4;1;$percentClamped`a")
		return
	}

	Write-Progress -Completed
	Write-Host -NoNewline ("`e]9;4;0`a")
}

function ReadHost {
	[cmdletbinding()]
	param (
		$query
	)

	Write-Host "`a"
	return Read-Host -Prompt $query
}

# Write progress to the terminal as well as the progress bar
function WriteProgress {
	[CmdletBinding()]
	param (
		$progressObject,
		[switch]$initiate,
		[switch]$finished,
		$title,
		$totalActions,
		$updateFrequencySeconds = 1
	)

	if ($initiate) {
		if (-not $title) {
			Write-Error "Need a title for the progress"
			return
		}
		$progressObject = New-Object -TypeName psobject
		$progressObject | Add-Member NoteProperty title $title
		if ($totalActions) {
			$progressObject | Add-Member NoteProperty total $totalActions
		}
		$progressObject | Add-Member NoteProperty current 0
		$timer = [System.Diagnostics.Stopwatch]::StartNew()
		$progressObject | Add-Member NoteProperty time $timer
		$progressObject | Add-Member NoteProperty lastsecond 0
		$progressObject | Add-Member NoteProperty updatefrequency $updateFrequencySeconds
		return $progressObject
	}

	if (-not $progressObject) {
		Write-Error "Need a progress object, run -initiate first"
		return
	}

	if ($finished) {
		SetTerminalProgress
		return
	}

	$progressObject.current = $progressObject.current + 1
	$elapsedSeconds = $progressObject.time.Elapsed.TotalSeconds
	if ($elapsedSeconds - $progressObject.lastsecond -lt $progressObject.updatefrequency) {
		return
	}

	if (-not $progressObject.total) {
		Write-Progress -Activity $progressObject.title -Status "$($progressObject.current) processed"
		SetTerminalProgress -unknown
		return
	}

	$progressObject.lastsecond = $elapsedSeconds
	$percent = (($progressObject.current / $progressObject.total) * 100)
	$status = "($($progressObject.current)/$($progressObject.total))"
	$secondsLeft = New-TimeSpan -Seconds ([decimal]::round($elapsedSeconds / $percent * (100 - $percent)))
	SetTerminalProgress -progressPercent $percent
	Write-Progress -Activity $progressObject.title -Status "$status - $secondsLeft remaining" -PercentComplete $percent
}

# Shows the rimworld log progress
function Get-RimworldLog {
	param(
		$initialRows = 10
	)

	$Host.UI.RawUI.WindowTitle = "RimWorld Log"
	$logFile = "$env:USERPROFILE\Appdata\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Player.log"
	while ($true) {
		if (-not (Test-Path $logFile)) {
			Start-Sleep -Seconds 1
			continue
		}
		Get-content $logFile -Tail $initialRows -Wait -ErrorAction SilentlyContinue | ForEach-Object { Write-Host -ForegroundColor (Get-LogColor $_) $_ }
	}
}

# Colorizes the log-entries
function Get-LogColor {
	param($logRow)

	process {
		if ($logRow -match "debug" -or $logRow -match "\[Ref" -or $logRow -match "Fallback handler could not load library") {
			return "DarkGray"
		}
		if ($logRow -match "warning") {
			return "Yellow"
		}
		if (($logRow -match "error" -and $logRow -notmatch "ModErrorChecker") -or $logRow -match "exception" -or $logRow -match "fail" -or $logRow -match " at .* \<.*\>") {
			return "Red"
		}
		return "White"
	}
}

# First get the settings from the json-file
$settingsFilePath = "$PSScriptRoot\settings.json"
if (-not (Test-Path $settingsFilePath)) {
	WriteMessage -failure "Could not find settingsfile: $settingsFilePath, exiting."
	return
}
$Global:settings = Get-Content -Path $settingsFilePath -raw -Encoding UTF8 | ConvertFrom-Json
$Global:localModFolder = "$($settings.rimworld_folder_path)\Mods"
$Global:oldRimworldFolder = $settings.old_rimworld_folders
$Global:playingModsConfig = "$PSScriptRoot\ModsConfig_Playing.xml"
$Global:moddingModsConfig = "$PSScriptRoot\ModsConfig_Modding.xml"
$Global:testingModsConfig = "$PSScriptRoot\ModsConfig_Testing.xml"
$Global:autoModsConfig = "$PSScriptRoot\ModsConfig_Auto.xml"
$Global:bareModsConfig = "$PSScriptRoot\ModsConfig_Bare.xml"
$Global:replacementsFile = "$PSScriptRoot\ReplaceRules.txt"
$Global:fundingFile = $settings.funding_path
$Global:openAIApiKey = $settings.openai_api_key
$Global:openAIModel = $settings.openai_model
$Global:openAIChatModel = $settings.openai_chat_model
$Global:visualStudioPath = $settings.visual_studio_path
$Global:manifestTemplate = "$PSScriptRoot\$($settings.manfest_template)"
$Global:assetCountLimit = $settings.asset_count_limit
$Global:assetSizeLimit = $settings.asset_max_size_mb * 1MB
$Global:assetSizeLimitMb = "$($settings.asset_max_size_mb) mb"
$Global:databaseString = $settings.database_string
if (-not (Test-Path $manifestTemplate)) {
	WriteMessage -failure "Manifest-template not found: $manifestTemplate, exiting."
	return
}
$Global:gitignoreTemplate = "$PSScriptRoot\$($settings.gitignore_template)"
if (-not (Test-Path $gitignoreTemplate)) {
	WriteMessage -failure "gitignore-template not found: $gitignoreTemplate, exiting."
	return
}
if (Test-Path $settings.gimp_folder) {
	$Global:gimpPath = (Get-ChildItem $settings.gimp_folder -Filter "gimp-*.exe")[0].FullName
}
$Global:publisherPlusTemplate = "$PSScriptRoot\$($settings.publisher_plus_template)"
$Global:rimTransTemplate = "$PSScriptRoot\$($settings.rimtrans_template)"
$Global:updatefeaturesTemplate = "$PSScriptRoot\$($settings.updatefeatures_template)"
$Global:updateinfoTemplate = "$PSScriptRoot\$($settings.updateinfo_template)"
$Global:modSyncTemplate = "$PSScriptRoot\$($settings.modsync_template)"
$Global:licenseFile = "$PSScriptRoot\$($settings.license_file)"
$Global:unityPath = $settings.unity_path
if ($unityPath.Contains("*")) {
	$possiblePaths = Get-Item -Path $unityPath
	$unityPath = $possiblePaths | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}
$Global:unityBundleProjectPath = $($settings.unity_bundle_project_path)
$Global:discordUpdateMessage = "$PSScriptRoot\$($settings.discord_update_message)"
$Global:discordPublishMessage = "$PSScriptRoot\$($settings.discord_publish_message)"
$Global:discordRemoveMessage = "$PSScriptRoot\$($settings.discord_remove_message)"
$Global:discordUpdateHookUrl = $settings.discord_update_hook_url
$Global:discordPublishHookUrl = $settings.discord_publish_hook_url
$Global:discordRemoveHookUrl = $settings.discord_remove_hook_url
$Global:discordTestHookUrl = $settings.discord_test_hook_url
$Global:discordHookUrl = $settings.discord_remove_hook_url
$Global:discordServerId = $settings.discord_serverId
$Global:trelloKey = $settings.trello_api_key
$Global:trelloToken = $settings.trello_api_token
$Global:trelloBoardId = $settings.trello_board_id
$Global:steamApiKey = $settings.steam_api_key
$Global:deeplApiKey = $settings.deepl_api_key
$Global:deeplApiUrl = $settings.deepl_api_url
$Global:kofiUrl = $settings.kofi_url
$Global:rimWorldBaseApiKey = $settings.rimworldbase_api_key
$Global:rimWorldBaseApiUrl = $settings.rimworldbase_api_url
$Global:rimWorldBaseApiUser = $settings.rimworldbase_api_user

if (-not $Global:SteamThrottleState) {
	$Global:SteamThrottleState = [ordered]@{
		WaitSeconds = 0.0
		LastAttempt = [datetime]::MinValue
		LastSuccess = [datetime]::MinValue
	}
}

function Get-SteamThrottleWaitSeconds {
	if (-not $Global:SteamThrottleState) {
		$Global:SteamThrottleState = [ordered]@{
			WaitSeconds = 0.0
			LastAttempt = [datetime]::MinValue
			LastSuccess = [datetime]::MinValue
		}
	}
	$state = $Global:SteamThrottleState
	if ($state.LastAttempt -eq [datetime]::MinValue) {
		return 0.0
	}
	$elapsed = (Get-Date) - $state.LastAttempt
	$remaining = $state.WaitSeconds - $elapsed.TotalSeconds
	if ($remaining -lt 0) {
		return 0.0
	}
	return $remaining
}

function Set-SteamThrottleAttempt {
	if (-not $Global:SteamThrottleState) {
		$Global:SteamThrottleState = [ordered]@{
			WaitSeconds = 0.0
			LastAttempt = [datetime]::MinValue
			LastSuccess = [datetime]::MinValue
		}
	}
	$Global:SteamThrottleState.LastAttempt = Get-Date
}

function Update-SteamThrottleState {
	[CmdletBinding()]
	param(
		[switch]$Success,
		[switch]$Failure
	)

	if (-not $Global:SteamThrottleState) {
		$Global:SteamThrottleState = [ordered]@{
			WaitSeconds = 0.0
			LastAttempt = [datetime]::MinValue
			LastSuccess = [datetime]::MinValue
		}
	}
	$state = $Global:SteamThrottleState
	$minWait = 5.0
	$maxWait = 300.0
	if ($Failure) {
		if ($state.WaitSeconds -lt $minWait) {
			$state.WaitSeconds = $minWait
		} else {
			$state.WaitSeconds = [math]::Min($maxWait, $state.WaitSeconds * 2.0)
		}
	}
	if ($Success -and $state.WaitSeconds -gt 0) {
		if ($state.WaitSeconds -lt 1.0) {
			$state.WaitSeconds = 0.0
		} else {
			$state.WaitSeconds = $state.WaitSeconds / 2.0
		}
		$state.LastSuccess = Get-Date
	}
	$Global:SteamThrottleState = $state
}

function Invoke-SteamThrottleWait {
	[CmdletBinding()]
	param(
		[string]$Reason
	)

	$waitSeconds = Get-SteamThrottleWaitSeconds
	if ($waitSeconds -le 0) {
		return
	}
	$sleepSeconds = [math]::Ceiling($waitSeconds)
	if ($Reason) {
		WriteMessage -progress "Waiting $sleepSeconds seconds before $Reason due to Steam throttle"
	} else {
		WriteMessage -progress "Waiting $sleepSeconds seconds due to Steam throttle"
	}
	Start-Sleep -Seconds $sleepSeconds
}
$Global:nugetPackagesPath = $settings.nuget_packages_path
$Global:autoTranslateLanguages = $settings.auto_translate_languages
if (-not (Test-Path "$($settings.mod_staging_folder)\..\modlist.json")) {
	"{}" | Out-File -Encoding utf8 -FilePath "$($settings.mod_staging_folder)\..\modlist.json"
}
$Global:modlist = Get-Content "$($settings.mod_staging_folder)\..\modlist.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$Global:languages = @("Bulgarian", "Czech", "Danish", "German", "Greek", "English (British)", "English", "Spanish", "Estonian", "Finnish", "French", "Hungarian", "Indonesian", "Italian", "Japanese", "Lithuanian", "Latvian", "Dutch", "Polish", "Portuguese", "Portuguese (Brazilian)", "Romanian", "Russian", "Slovak", "Slovenian", "Swedish", "Turkish", "ChineseSimplified")
$Global:shorts = @("BG","CS","DA","DE","EL","EN-GB","EN-US","ES","ET","FI","FR","HU","ID","IT","JA","LT","LV","NL","PL","PT-PT","PT-BR","RO","RU","SK","SL","SV","TR","ZH")
$Global:faqText = $settings.faq_text
$Global:faqTextPrivate = $settings.faq_text_private
$Global:globalRequestLog = @()
if (-not $Global:ModInfoCache) {
 $Global:ModInfoCache = @{}
}

Add-Type -TypeDefinition @"
public enum ModCodeSize {
    None = 0,
    Tiny = 1,
    Small = 2,
    Medium = 3,
    Large = 4,
    Huge = 5
}
"@

# Converts BB-steam text to Github format
function Convert-BBCodeToGithub {
	param($textToConvert)
	$textToConvert = $textToConvert.Replace("[b]", "**").Replace("[/b]", "**")
	$textToConvert = $textToConvert.Replace("[i]", "*").Replace("[/i]", "*")
	$textToConvert = $textToConvert.Replace("[strike]", "~~").Replace("[/strike]", "~~")
	$textToConvert = $textToConvert.Replace("[u]", "<ins>").Replace("[/u]", "</ins>")
	$textToConvert = $textToConvert.Replace("[h1]", "# ").Replace("[/h1]", "`n")
	$textToConvert = $textToConvert.Replace("[h2]", "## ").Replace("[/h2]", "`n")
	$textToConvert = $textToConvert.Replace("[h3]", "### ").Replace("[/h3]", "`n")
	$textToConvert = $textToConvert -replace '\[img\]([^\]]*)\[/img\]',"![Image]($('$1'))"
	$textToConvert = $textToConvert -replace ".png\)\n([^\n])",".png)`n`n$('$1')"
	$textToConvert = $textToConvert -replace '\[url=([^\]]*)\]([^\]]*)\[\/url\]','[$2]($1)'
	$textToConvert = $textToConvert -replace '\[url=([^\]]*)\](.*)\[\/url\]','[$2]($1)'
	$textToRemove = (($textToConvert -split "\[table\]")[1] -split "\[/table\]")[0]
	$textToConvert = $textToConvert.Replace("`n[table]$textToRemove[/table]`n", "")
	$textToConvert = $textToConvert.Replace("[list]", "`n").Replace("[/list]", "`n").Replace("[*]", "- ")

	return $textToConvert
}


function Get-MultilineMessage {
	param (
		$query,
		[switch]$mustFill
	)
	$returnValue = ""
	while (-not $returnValue) {
		$message = "$query (two blank rows ends message, to skip just press enter)"
		if ($mustFill) {
			$message = "$query (two blank rows ends message)"
		}
		Write-Host "$addon$message"
		$continueMessage = $true
		$currentMessage = @()
		$lastRow = ""
		while ($continueMessage) {
			$currentRow = ReadHost
			if ($currentRow -eq "" -and $currentMessage.Count -eq 0) {
				break
			}
			if ($currentRow -eq "" -and $lastRow -eq "") {
				$continueMessage = $false
				continue
			}
			$currentMessage += $currentRow
			$lastRow = $currentRow
		}

		$returnValue = $currentMessage -join "`r`n"
		if ($mustFill) {
			$addon = "Must write something! "
		} else {
			break
		}
	}
	$returnValue = $returnValue.Trim()
	return $returnValue
}

function Open-DiscordChannel {
	param(
		$channelId
	)

	$discordPath = (get-process discord -ErrorAction SilentlyContinue).path | Get-Unique

	if (-not $discordPath) {
		WriteMessage -message "No Discord instance running, start it first" -failure
		return
	}

	$process = Start-Process -FilePath $discordPath -ArgumentList " --url -- ""discord://discordapp.com/channels/$discordServerId/$channelId""" -PassThru -RedirectStandardOutput Out-Null
	Start-Sleep -Seconds 1
	$process | Stop-Process
}


function Update-ModSkillFormat {
	param(
		$filePath
	)

	if (-not (Test-Path $filePath)) {
		WriteMessage -message "No file found at $filePath" -failure
		return
	}

	(Get-Content -Raw $filePath) -replace '<li>\s*<key>(.*)</key>\s*<value>(.*)</value>\s*</li>', '<$1>$2</$1>' | Out-File $filePath
	WriteMessage -message "Replaced the skill format in $filePath" -success
}


function Get-UriExists {
	param(
		[string]$uriToCheck
	)

	try {
		$req = [System.Net.WebRequest]::Create($uriToCheck)
		$req.Method = "HEAD"
		$resp = $req.GetResponse()
		$resp.Close()
		return $true
	} catch {
		return $false
	}
}

function Get-Mod {
	param(
		[string]$modName,
		[string]$publishedId,
		[string]$modPath,
		$originalModObject,
		[switch]$noTypes,
		[switch]$fast
	)

	if ($originalModObject) {
		$modPath = $originalModObject.ModFolderPath
	}

	if (-not $modName -and -not $modPath) {
		$modName = Get-CurrentModNameFromLocation
	}
	$modObject = [ordered]@{}
	if ($publishedId) {
		$modObject.PublishedId = $publishedId
		$modObject.ModUrl = "https://steamcommunity.com/sharedfiles/filedetails/?id=$($modObject.PublishedId)"
		if ($modName) {
			$modObject.Name = $modName
		}
		return $modObject
	}

	if ($modPath) {
		$modObject.ModFolderPath = $modPath
		$modObject.Name = Split-Path -Leaf -Path $modObject.ModFolderPath
	} elseif (-not $modName) {
		return
	} else {
		$modObject.ModFolderPath = "$localModFolder\$modName"
		$modObject.Name = $modName
	}

	if (-not (Test-Path $modObject.ModFolderPath)) {
		WriteMessage -error "Cannot find mod at $($modObject.ModFolderPath)"
		return
	}

	$modObject.NameClean = $modObject.Name.Replace("+", "Plus")
	$modObject.AboutFilePath = "$($modObject.ModFolderPath)\About\About.xml"
	if (-not (Test-Path $modObject.AboutFilePath)) {
		WriteMessage -error "Cannot find about-file at $($modObject.AboutFilePath)"
		$modObject.AboutFilePath = $null
		return $modObject
	}

	$modObject.AboutFileContent = Get-Content $modObject.AboutFilePath -Raw -Encoding UTF8
	$modObject.AboutFileXml = [xml]$modObject.AboutFileContent
	$modObject.DisplayName = $modObject.AboutFileXml.ModMetaData.name
	$modObject.Author = $modObject.AboutFileXml.ModMetaData.author
	$modObject.SupportedVersions = $modObject.AboutFileXml.ModMetaData.supportedVersions.li
	# Check if any of the supported version has not been released yet, if so, remove it
	$currentRimworldVersion = Get-CurrentRimworldVersion -versionObject
	$modObject.SupportedVersions = $modObject.SupportedVersions | Where-Object { [version]$_ -le $currentRimworldVersion }
	if ($modObject.SupportedVersions.Count -gt 1) {
		$modObject.HighestSupportedVersion = ($modObject.SupportedVersions | Sort-Object)[-1]
	} else {
		$modObject.HighestSupportedVersion = $modObject.SupportedVersions
		$modObject.SupportedVersions = @( $modObject.SupportedVersions )
	}
	$modObject.Description = $modObject.AboutFileXml.ModMetaData.description
	if ($modObject.Description -and $modObject.Description.GetType().Name -eq "XmlElement") {
		$modObject.Description = $modObject.Description.'#cdata-section'
	}
	# In markdown, & is escaped as &amp;, so we need to convert it here, also windows new line is two characters
	if ($modObject.Description) {
		$modObject.DescriptionLength = $modObject.Description.Replace('&', '&amp;').Replace("`n", ".`n").Length
	} else {
		$modObject.DescriptionLength = 0
	}
	$modObject.ModId = $modObject.AboutFileXml.ModMetaData.packageId
	if ($modObject.ModId) {
		$modObject.Mine = $modObject.ModId.StartsWith("Mlie.")
	} else {
		$modObject.Mine = $false
	}

	if ($noTypes -or $fast) {
		$modObject.HasXml = $false
		$modObject.HasAssemblies = $false
	} else {
		$modObject.HasXml = (Get-ChildItem $modObject.ModFolderPath -Directory -Recurse | ForEach-Object { if ($_.Name -eq "Defs" -or $_.Name -eq "Patches") {
					return $true
				} } ) -eq $true
		$modObject.HasAssemblies = (Get-ChildItem $modObject.ModFolderPath -Directory -Recurse | ForEach-Object { if ($_.Name -eq "Assemblies") {
					return $true
				} } ) -eq $true
	}

	$modObject.PublishedIdFilePath = "$($modObject.ModFolderPath)\About\PublishedFileId.txt"
	if (Test-Path $modObject.PublishedIdFilePath) {
		$modObject.Published = $true
		$modObject.PublishedId = Get-Content $modObject.PublishedIdFilePath -Raw
		$modObject.ModUrl = "https://steamcommunity.com/sharedfiles/filedetails/?id=$($modObject.PublishedId)"
	} else {
		if ($modObject.ModFolderPath -like "*workshop*") {
			WriteMessage -warning "Mod seems to be a workshop mod, but has no PublishedFileId.txt, assuming id from foldername"
			$modObject.PublishedId = Split-Path -Leaf -Path $modObject.ModFolderPath
			$modObject.ModUrl = "https://steamcommunity.com/sharedfiles/filedetails/?id=$($modObject.PublishedId)"
			$modObject.Published = $true
		} else {
			$modObject.Published = $false
			$modObject.PublishedId = $null
			$modObject.ModUrl = $null
			$modObject.PublishedIdFilePath = $null
		}
	}

	$modObject.LoadFoldersPath = "$($modObject.ModFolderPath)\LoadFolders.xml"
	if (-not (Test-Path $modObject.LoadFoldersPath)) {
		$modObject.LoadFoldersPath = $null
	}

	$modObject.PreviewFilePath = "$($modObject.ModFolderPath)\About\Preview.png"
	if (-not (Test-Path $modObject.PreviewFilePath)) {
		$modObject.PreviewFilePath = $null
	}

	if (-not $modObject.Mine -or $modObject.ModFolderPath.Contains("workshop")) {
		return $modObject
	}

	$modObject.ManifestFilePath = "$($modObject.ModFolderPath)\About\Manifest.xml"
	if (Test-Path $modObject.ManifestFilePath) {
		$modObject.ManifestFileContent = Get-Content $modObject.ManifestFilePath -Raw -Encoding UTF8
		$modObject.ManifestFileXml = [xml]$modObject.ManifestFileContent
		$modObject.Version = $modObject.ManifestFileXml.Manifest.version
	} else {
		$modObject.ManifestFilePath = $null
	}
	$modObject.ModSyncFilePath = "$($modObject.ModFolderPath)\About\ModSync.xml"
	if (Test-Path $modObject.ModSyncFilePath) {
		$modObject.ModSyncFileContent = Get-Content $modObject.ModSyncFilePath -Raw -Encoding UTF8
		$modObject.ModSyncFileXml = [xml]$modObject.ModSyncFileContent
	} else {
		$modObject.ModSyncFilePath = $null
	}

	$modObject.ModIconPath = "$($modObject.ModFolderPath)\Textures\ModIcon\$($modObject.NameClean).png"
	if (-not (Test-Path $modObject.ModIconPath)) {
		$modObject.ModIconPath = "$($modObject.ModFolderPath)\About\ModIcon.png"
	}

	if (-not (Test-Path $modObject.ModIconPath)) {
		$modObject.ModIconPath = $null
	}

	$modObject.ChangelogPath = "$($modObject.ModFolderPath)\About\Changelog.txt"
	if (-not (Test-Path $modObject.ChangelogPath)) {
		$modObject.ChangelogPath = $null
	}
	$modObject.ReadMePath = "$($modObject.ModFolderPath)\README.md"
	if (-not (Test-Path $modObject.ReadMePath)) {
		$modObject.ReadMePath = $null
	}

	$modObject.LicensePath = "$($modObject.ModFolderPath)\LICENSE.md"
	if (-not (Test-Path $modObject.LicensePath)) {
		$modObject.LicensePath = $null
	}

	$modObject.GitIgnorePath = "$($modObject.ModFolderPath)\.gitignore"
	if (-not (Test-Path $modObject.GitIgnorePath)) {
		$modObject.GitIgnorePath = $null
	}

	$modObject.ModPublisherPath = "$($modObject.ModFolderPath)\_PublisherPlus.xml"
	if (-not (Test-Path $modObject.ModPublisherPath)) {
		$modObject.ModPublisherPath = $null
	}
	$modObject.Continued = $modObject.DisplayName.EndsWith(" (Continued)")

	if (Test-Path "$($modObject.ModFolderPath)\AssetBundles") {
		$modObject.AssetBundlesPath = "$($modObject.ModFolderPath)\AssetBundles"
		$modObject.AssetSourcePath = "$($modObject.ModFolderPath)\Source\Assets"
		$modObject.UsesAssetBundle = $true
		$modObject.UsesRegularAssets = $false
	} elseif (Test-Path "$($modObject.ModFolderPath)\Assets\AssetBundles") {
		$modObject.AssetBundlesPath = "$($modObject.ModFolderPath)\Assets\AssetBundles"
		$modObject.AssetSourcePath = "$($modObject.ModFolderPath)\LegacyAssets"
		$modObject.UsesAssetBundle = $true
		$modObject.UsesRegularAssets = $true
	} else {
		$modObject.UsesRegularAssets = $true
		$modObject.UsesAssetBundle = $false
		$modObject.AssetBundlesPath = $null
		$modObject.AssetSourcePath = $null
	}

	$modObject.DescriptionClean = $modObject.Description
	if (-not $modObject.Continued) {
		if ($modObject.DescriptionClean.Contains("[img]https://img.litet.net/logos/Self-Info.png[/img]")) {
			$start = "[img]https://img.litet.net/logos/Self-Info.png[/img]"
			$stop = "[table]"
			$modObject.DescriptionClean = $modObject.DescriptionClean.Substring($modObject.DescriptionClean.IndexOf($start) + $start.Length)
			$modObject.DescriptionClean = $modObject.DescriptionClean.Substring(0, $modObject.DescriptionClean.IndexOf($stop) - 1)
		}
	} else {
		if ($modObject.DescriptionClean.Contains("[img]https://img.litet.net/logos//Notice.png[/img]") -and
			$modObject.DescriptionClean.Contains("[img]https://img.litet.net/logos/OriginalDescription.png[/img]") -and
			$modObject.DescriptionClean.Contains("[img]https://img.litet.net/logos/ReportingIssues.png[/img]")) {
			$middlestop = "[img]https://img.litet.net/logos/Notice.png[/img]"
			$start = "[img]https://img.litet.net/logos/OriginalDescription.png[/img]"
			$stop = "[img]https://img.litet.net/logos/ReportingIssues.png[/img]"
			$modObject.DescriptionClean = $modObject.DescriptionClean.Substring($modObject.DescriptionClean.IndexOf($start) + $start.Length)
			$modObject.DescriptionClean = $modObject.DescriptionClean.Substring(0, $modObject.DescriptionClean.IndexOf($stop) - 1)
			$modObject.DescriptionClean = "$($modObject.Description.Substring(0, $modObject.Description.IndexOf($middlestop) - 1))`n$($modObject.DescriptionClean)"
		}
		if ($modObject.Continued -and (Test-Path "$($modObject.ModFolderPath)\Source\PublishedFileId.txt")) {
			$modObject.OriginalPublishedId = (Get-Content "$($modObject.ModFolderPath)\Source\PublishedFileId.txt" -Raw).Trim()
		}
	}
	$modObject.DescriptionClean = $modObject.DescriptionClean -replace "\[url=.*?\](.*?)\[/url\]", '$1'
	$modObject.DescriptionClean = $modObject.DescriptionClean -replace "\[.*?\]", ""
	$modObject.DescriptionClean = $modObject.DescriptionClean -replace "https?://\S+", ""

	$modObject.Repository = "https://github.com/$($settings.github_username)/$($modObject.NameClean)"
	$modObject.MetadataFilePath = "$($modObject.ModFolderPath)\Source\metadata.json"
	if (-not (Test-Path $modObject.MetadataFilePath)) {
		WriteMessage -progress "Could not find metadata-file, creating"
		$metaJson = ("
		[
			{
				'Continued' : '',
				'CanAdd': '',
				'CanRemove': ''
			}
		]
		") | ConvertFrom-Json
		$metaJson.Continued = $modObject.Continued
		$metaJson | ConvertTo-Json | Set-Content -Path $modObject.MetadataFilePath -Force -Encoding UTF8
	}

	$modObject.MetadataFileContent = Get-Content -Path $modObject.MetadataFilePath -raw -Encoding UTF8
	$modObject.MetadataFileJson = $modObject.MetadataFileContent | ConvertFrom-Json

	return $modObject
}

#endregion

#region GitHub functions

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

# Easy load of a mods git-repo
function Get-ModRepository {
	param(
		$modObject,
		[switch]$getLink
	)
	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not $modObject.Repository) {
		$modObject.Repository = "https://github.com/$($settings.github_username)/$($modObject.NameClean)"
	}

	if ($getLink) {
		return $modObject.Repository
	}

	$applicationPath = $settings.browser_path
	Start-Process -FilePath $applicationPath -ArgumentList $modObject.Repository
	Start-Sleep -Seconds 1
	Remove-Item "$($modObject.ModFolderPath)\debug.log" -Force -ErrorAction SilentlyContinue
}

# Creates a new empty github repository
function New-GitRepository {
	param(
		$repoName
	)
	if ((Get-RepositoryStatus -repositoryName $repoName) -eq $true) {
		WriteMessage -failure "Repository $repoName already exists"
		return
	}
	$repoData = @{
		name       = $repoName;
		visibility = "public";
		auto_init  = "false";
		has_issues = "true"
	}
	$repoParams = @{
		Uri         = "https://api.github.com/user/repos";
		Method      = 'POST';
		Headers     = @{
			Authorization = 'Basic ' + [Convert]::ToBase64String(
				[Text.Encoding]::ASCII.GetBytes($settings.github_api_token + ":x-oauth-basic"));
		}
		ContentType = 'application/json';
		Body        = (ConvertTo-Json $repoData -Compress)
	}
	WriteMessage -progress "Creating repo"
	Invoke-RestMethod @repoParams | Out-Null
	Start-Sleep -Seconds 1
	WriteMessage -success "Done"
}

# Archives a github repository
function Set-GitRepositoryToArchived {
	param(
		$repoName
	)

	if (-not $repoName) {
		$repoName = Get-CurrentModNameFromLocation
	}
	if (-not (Get-RepositoryStatus -repositoryName $repoName)) {
		WriteMessage -failure "Repository $repoName does not exist"
		return
	}
	$repoData = @{
		archived = "true";
	}
	$repoParams = @{
		Uri         = "https://api.github.com/repos/$($settings.github_username)/$repoName";
		Method      = 'PATCH';
		Headers     = @{
			Authorization = 'Basic ' + [Convert]::ToBase64String(
				[Text.Encoding]::ASCII.GetBytes($settings.github_api_token + ":x-oauth-basic"));
		}
		ContentType = 'application/json';
		Body        = (ConvertTo-Json $repoData -Compress)
	}
	WriteMessage -progress "Archiving repo"
	Invoke-RestMethod @repoParams | Out-Null
	Start-Sleep -Seconds 1
	WriteMessage -success "Done"
}

# Changes the default repo branch
function Set-DefaultGitBranch {
	param(
		$repoName,
		$branchName
	)

	if (-not $repoName) {
		$repoName = Get-CurrentModNameFromLocation
	}
	$repoNameClean = $repoName.Replace("+", "Plus")
	if (-not (Get-RepositoryStatus -repositoryName $repoNameClean)) {
		WriteMessage -failure "Repository $repoName does not exist"
		return
	}
	$repoData = @{
		default_branch = "$branchName"
	}
	$repoParams = @{
		Uri         = "https://api.github.com/repos/$($settings.github_username)/$repoNameClean";
		Method      = 'PATCH';
		Headers     = @{
			Authorization = 'Basic ' + [Convert]::ToBase64String(
				[Text.Encoding]::ASCII.GetBytes($settings.github_api_token + ":x-oauth-basic"));
		}
		ContentType = 'application/json';
		Body        = (ConvertTo-Json $repoData -Compress)
	}
	WriteMessage -progress "Changing repo default to $branchName for $repoName"
	Invoke-RestMethod @repoParams | Out-Null
	Start-Sleep -Seconds 1
	WriteMessage -success "Done"
}

# Sets the issues-status on a repository
function Set-IssuesActive {
	param(
		$repoName,
		$status = "true"
	)

	if (-not $repoName) {
		$repoName = Get-CurrentModNameFromLocation
	}
	$repoNameClean = $repoName.Replace("+", "Plus")
	if (-not (Get-RepositoryStatus -repositoryName $repoNameClean)) {
		WriteMessage -failure "Repository $repoName does not exist"
		return
	}
	$repoData = @{
		has_issues = "$status"
	}
	$repoParams = @{
		Uri         = "https://api.github.com/repos/$($settings.github_username)/$repoNameClean";
		Method      = 'PATCH';
		Headers     = @{
			Authorization = 'Basic ' + [Convert]::ToBase64String(
				[Text.Encoding]::ASCII.GetBytes($settings.github_api_token + ":x-oauth-basic"));
		}
		ContentType = 'application/json';
		Body        = (ConvertTo-Json $repoData -Compress)
	}
	WriteMessage -progress "Setting issues to $status for $repoName"
	Invoke-RestMethod @repoParams | Out-Null
	Start-Sleep -Seconds 1
	WriteMessage -success "Done"
}

function Get-GithubRepoInfo {
	param(
		$repoName
	)

	if (-not $repoName) {
		$repoName = Get-CurrentModNameFromLocation
	}
	if (-not (Get-RepositoryStatus -repositoryName $repoName)) {
		WriteMessage -failure "Repository $repoName does not exist"
		return
	}
	$repoParams = @{
		Uri         = "https://api.github.com/repos/$($settings.github_username)/$repoName"
		Method      = 'GET'
		Headers     = @{
			Authorization = 'Basic ' + [Convert]::ToBase64String(
				[Text.Encoding]::ASCII.GetBytes($settings.github_api_token + ":x-oauth-basic"))
		}
		ContentType = 'application/json'
	}

	try {
		$repo = Invoke-RestMethod @repoParams
	} catch {
		return $false
	}
	return $repo
}

# Fetches subscription-status of a github repo
function Get-GitSubscriptionStatus {
	param(
		$repoName
	)

	if (-not $repoName) {
		$repoName = Get-CurrentModNameFromLocation
	}
	if (-not (Get-RepositoryStatus -repositoryName $repoName)) {
		WriteMessage -failure "Repository $repoName does not exist"
		return
	}
	$repoParams = @{
		Uri         = "https://api.github.com/repos/$($settings.github_username)/$repoName/subscription"
		Method      = 'GET'
		Headers     = @{
			Authorization = 'Basic ' + [Convert]::ToBase64String(
				[Text.Encoding]::ASCII.GetBytes($settings.github_api_token + ":x-oauth-basic"))
		}
		ContentType = 'application/json'
	}
	try {
		$repoStatus = Invoke-RestMethod @repoParams
	} catch {
		return $false
	}
	return $repoStatus.subscribed
}

# Sets subscription-status of a github repo
function Set-GitSubscriptionStatus {
	param(
		$repoName,
		[bool]$enabled
	)

	if (-not $repoName) {
		$repoName = Get-CurrentModNameFromLocation
	}
	if (-not (Get-RepositoryStatus -repositoryName $repoName)) {
		WriteMessage -failure "Repository $repoName does not exist"
		return
	}
	$repoData = @{
		subscribed = $enabled
	}
	$repoParams = @{
		Uri         = "https://api.github.com/repos/$($settings.github_username)/$repoName/subscription"
		Method      = 'PUT'
		Headers     = @{
			Authorization = 'Basic ' + [Convert]::ToBase64String(
				[Text.Encoding]::ASCII.GetBytes($settings.github_api_token + ":x-oauth-basic"))
		}
		ContentType = 'application/json'
		Body        = (ConvertTo-Json $repoData -Compress)
	}
	WriteMessage -progress "Setting status for $repoName to $enabled"
	try {
		Invoke-RestMethod @repoParams | Out-Null
	} catch {
		return $false
	}
	return $true
}


function Get-GitPullRequests {
	param(
		$repoName,
		[switch]$alsoClosed
	)
	if (-not $repoName) {
		$repoName = Get-CurrentModNameFromLocation
	}
	if (-not (Get-RepositoryStatus -repositoryName $repoName)) {
		WriteMessage -failure "Repository $repoName does not exist"
		return
	}
	$state = "open"
	if ($alsoClosed) {
		$state = "all"
	}
	$repoParams = @{
		Uri         = "https://api.github.com/repos/$($settings.github_username)/$repoName/pulls?state=$state"
		Method      = 'GET'
		Headers     = @{
			Authorization = 'Basic ' + [Convert]::ToBase64String(
				[Text.Encoding]::ASCII.GetBytes($settings.github_api_token + ":x-oauth-basic"))
		}
		ContentType = 'application/json'
	}
	try {
		$pullRequests = Invoke-RestMethod @repoParams
	} catch {
		WriteMessage -progress "Found no pull requests for repo $repoName $_"
		return
	}
	if ($pullRequests.GetType().Name -ne "Object[]") {
		return @($pullRequests)
	}
	return $pullRequests
}


function Merge-GitPullRequest {
	param(
		$repoName,
		$pullRequestNumber,
		[switch]$silent,
		[switch]$openAfter
	)
	if (-not $repoName) {
		$repoName = Get-CurrentModNameFromLocation
	}
	if (-not (Get-RepositoryStatus -repositoryName $repoName)) {
		WriteMessage -failure "Repository $repoName does not exist"
		return
	}
	$repoData = @{
		subscribed = $enabled
	}
	$repoParams = @{
		Uri         = "https://api.github.com/repos/$($settings.github_username)/$repoName/pulls/$pullRequestNumber/merge"
		Method      = 'PUT'
		Headers     = @{
			Authorization = 'Basic ' + [Convert]::ToBase64String(
				[Text.Encoding]::ASCII.GetBytes($settings.github_api_token + ":x-oauth-basic"))
		}
		ContentType = 'application/json'
		Body        = (ConvertTo-Json $repoData -Compress)
	}
	WriteMessage -progress "Merging pull request $pullRequestNumber for $repoName"
	try {
		Invoke-RestMethod @repoParams | Out-Null
	} catch {
		WriteMessage -failure "Failed to merge, $_"
		return $false
	}
	WriteMessage -success "Merge succeeded"
	if (-not $silent) {
		ReadHost "Get latest git-changes now? (Enter to fetch, all other breaks)"
	}
	$originalLocation = Get-Location
	if (Get-LocalModFolder -repoName $repoName) {
		Get-LatestGitVersion
	}
	Set-Location $originalLocation

	if ($openAfter) {
		Start-Process -FilePath $settings.browser_path -ArgumentList "https://github.com/$($settings.github_username)/$repoName/pull/$pullRequestNumber"
	}
	return $true
}


function Merge-ModPullRequests {
	param(
		[switch]$noPull,
		[switch]$noOpenAfter
	)
	$modName = Get-CurrentModNameFromLocation
	$openRequests = Get-GitPullRequests -repoName $modName

	if (-not $openRequests) {
		WriteMessage "No pull requests found"
		return
	}

	WriteMessage "Active Pull Requests"
	for ($i = 0; $i -lt $openRequests.Count; $i++) {
		Write-Host "$($i + 1): $($openRequests[$i].title) by $($openRequests[$i].user.login) ($($openRequests[$i].created_at))"
	}
	Write-Host ""

	$answer = ReadHost "Select PR to merge or empty to exit"

	if (-not $answer -or -not $openRequests[$answer - 1]) {
		WriteMessage -progress "Aborting merge"
		return
	}
	$selectedPullRequest = $openRequests[$answer - 1]

	WriteMessage "Selected PR $answer with id $($selectedPullRequest.id)"

	Merge-GitPullRequest -repoName $modName -pullRequestNumber $selectedPullRequest.number -silent:(-not $noPull) -openAfter:(-not $noOpenAfter)
}

function Sync-GitImgBotStatus {
	param(
		[switch]$all,
		$repoName
	)
	$repoNames = @()
	if ($all) {
		$cards = Find-TrelloCardByName -text "ImgBot"
		if (-not $cards) {
			WriteMessage -progress "No active ImgBot PRs"
			return
		}
		foreach ($card in $cards) {
			$repoNames += $card.name.Split(" ")[0]
		}
	} else {
		if (-not $repoName) {
			$repoName = Get-CurrentModNameFromLocation
		}

		$repoNameClean = $repoName.Replace("+", "Plus")
		if (-not (Get-RepositoryStatus -repositoryName $repoNameClean)) {
			WriteMessage -failure "Repository $repoName does not exist"
			return
		}
		$repoNames += $repoName
	}

	$count = 1
	foreach ($repo in $repoNames) {
		SetTerminalProgress -progressPercent ($count / $repoNames.Count * 100)
		$count++
		$currentPullRequests = Get-GitPullRequests -repoName $repo
		if ($currentPullRequests.Count -eq 0) {
			WriteMessage -progress "Repository $repo have no active pull requests"
			continue
		}

		foreach ($pullRequest in $currentPullRequests) {
			if ($pullRequest.title -ne "[ImgBot] Optimize images") {
				continue
			}
			WriteMessage -progress "Found pull request from ImgBot, merging $repo"
			Merge-GitPullRequest -repoName $repo -pullRequestNumber $pullRequest.number -silent
			break
		}
	}
	SetTerminalProgress
}

function Set-SafeGitFolder {
	$currentFolder = Get-Location

	if (-not (Test-Path "$($currentFolder.Path)\.git")) {
		WriteMessage -warning  "Folder is not a git-root folder, skipping safe-check"
		return
	}

	$safeFolders = git config --global --get-all safe.directory
	$translatedPath = $currentFolder.Path -replace "\\", "/"

	if ($safeFolders -contains $translatedPath) {
		return
	}

	WriteMessage -success "Adding folder to git safe-folders"
	git config --global --add safe.directory $translatedPath
}


function Get-GitOrigin {
	Set-SafeGitFolder
	git remote show origin
}


function Get-GitHistory {
	Set-SafeGitFolder
	git --no-pager log --date=format:'%Y-%m-%d' --pretty=format:'%C(bold blue)%cd%Creset - %s %C(yellow)%d%Creset' --abbrev-commit --reverse
}

# Simple push function for git, with optional reapply of gitignore
function Push-ModContent {
	param(
		[switch]$reapplyGitignore,
		$message
	)

	Set-SafeGitFolder
	$origin = git config --get remote.origin.url
	if ($origin -notlike "*$($settings.github_username)*") {
		$answer = ReadHost "Origin: $origin`nNot my repository, migrate? (y/n)"
		if ($answer -ne "y") {
			WriteMessage -failure "Not migrating, exiting"
			return
		}
		$repoName = Get-CurrentModNameFromLocation
		if (-not (Get-RepositoryStatus -repositoryName $repoName)) {
			WriteMessage -progress "Repository $repoName does not exist, creating"
			New-GitRepository -repoName $repoName
		}
		WriteMessage -progress "Migrating repository to $repoName"
		git remote set-url origin "$(Get-ModRepository -getLink).git"
		if (-not $message) {
			$message = "Importing mod from original repository"
		}
	} else {
		if (-not $message) {
			$message = ReadHost "Commit-Message"
		}
	}

	if ($reapplyGitignore) {
		git rm -r --cached .
	}
	git add .
	git commit -S -m $message
	git push origin
}

# Git-fetching function
# A simple function to update a local mod from a remote git server
function Get-LatestGitVersion {
	param (
		$modObject,
		[switch]$combineWithOriginal,
		[switch]$mineOnly,
		[switch]$newOnly,
		[switch]$clean,
		[switch]$force,
		[switch]$overwrite
	)
	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if ($clean) {
		Remove-Item "$($modObject.ModFolderPath)\.git" -Recurse -Force -Confirm:$false
	}
	if ($combineWithOriginal) {
		Set-Location $localModFolder
		Move-Item $modObject.ModFolderPath "$($modObject.ModFolderPath)_updated" -Force -Confirm:$false
		New-Item $modObject.ModFolderPath -ItemType Directory -Force | Out-Null
		Set-Location $modObject.ModFolderPath
	}
	if (Test-Path "$($modObject.ModFolderPath)\.git") {
		if ($newOnly) {
			return
		}
		Set-SafeGitFolder
		if ($overwrite) {
			WriteMessage -progress "Reseting git to remote state for $($modObject.Name)"
			git reset --hard HEAD
		}
		WriteMessage -progress "Fetching latest github for mod $($modObject.Name)"
		git pull origin main --allow-unrelated-histories
		return
	}
	WriteMessage -progress "Fetching latest github for mod $($modObject.Name)"
	if ($modObject.Mine) {
		$path = $modObject.Repository
	}
	if (-not $path -and $mineOnly) {
		WriteMessage -failure "$($modObject.Name) is not my mod, exiting"
		return
	}
	if (-not $path -and (Get-RepositoryStatus -repositoryName $($modObject.Name))) {
		$path = Get-ModRepository -getLink
	}
	if (-not $path) {
		$path = ReadHost "URL for the project"
	}

	if ((Get-ChildItem $($modObject.ModFolderPath)).Length -gt 0) {
		git init
		git remote add origin $path
		git fetch
		git config core.autocrlf true
		git add -A
		Update-GitRepoName -modObject $modObject
		git pull origin main
	} else {
		git clone $path $($modObject.ModFolderPath)
		Update-GitRepoName -modObject $modObject
	}
	Set-IssuesActive -repoName $($modObject.Name) -force:$force
	if ($combineWithOriginal) {
		# Remove everything in the original folder except the .git-folder
		Get-ChildItem $modObject.ModFolderPath | Where-Object { $_.Name -ne ".git" -and $_.Name -notlike "LICENSE*" } | Remove-Item -Recurse -Force
		Move-Item "$($modObject.ModFolderPath)_updated\*" $modObject.ModFolderPath -Force
		Remove-Item "$($modObject.ModFolderPath)_updated" -Force
	}
}

# Sets the branch-name to main instead of master
function Update-GitRepoName {
	param (
		$modObject
	)
	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not $modObject.Repository) {
		$modObject.Repository = "https://github.com/$($settings.github_username)/$($modObject.NameClean)"
	}

	$path = $modObject.Repository
	Set-SafeGitFolder
	if (-not (git ls-remote --heads $path master)) {
		WriteMessage -failure "$($modObject.Name) does not use the 'master' branch name, exiting"
		return
	}
	git switch -f master
	git branch -m master main
	git push -u origin main
	#git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
	git branch -u origin/main main
	Set-DefaultGitBranch -repoName $modObject.NameClean -branchName "main"
	git push origin --delete master
}

# Merges a repository with another, preserving history
function Merge-GitRepositories {
	param (
		$modObject
	)
	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not $modObject.Mine) {
		WriteMessage -failure "$($modObject.Name) is not mine, aborting merge"
		return
	}

	$modNameOld = "$($modObject.NameClean)_Old"
	Get-ModRepository -modObject $modObject
	ReadHost "Rename the current repository to $modNameOld, continue when done (Press ENTER)"
	ReadHost "Fork the repository to merge into, using the repository name $($modObject.Name), continue when done (Press ENTER)"

	$stagingDirectory = $settings.mod_staging_folder
	$rootFolder = Split-Path $stagingDirectory
	$version = [version]$modObject.ManifestFileXml.Manifest.version
	$newVersion = $version.ToString()

	Set-Location -Path $rootFolder
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse
	Write-Progress -Completed
	Set-Location -Path $stagingDirectory

	if (-not (Get-RepositoryStatus -repositoryName $modObject.NameClean)) {
		WriteMessage -failure "No repository found for $($modObject.NameClean)"
		Set-Location $modObject.ModFolderPath
		return
	}
	if (-not (Get-RepositoryStatus -repositoryName $modNameOld)) {
		WriteMessage -failure "No repository found for $modNameOld"
		Set-Location $modObject.ModFolderPath
		return
	}

	git clone https://github.com/$($settings.github_username)/$($modObject.NameClean)
	git clone https://github.com/$($settings.github_username)/$modNameOld


	Set-Location -Path $stagingDirectory\$($modObject.NameClean)
	$newBranch = ((cmd.exe /c git branch) | Out-String).Split(" ")[1].Split("`r")[0]

	Set-Location -Path $stagingDirectory\$modNameOld
	$oldBranch = ((cmd.exe /c git branch) | Out-String).Split(" ")[1].Split("`r")[0]

	git checkout $oldBranch
	git fetch --tags
	git branch -m master-holder
	git remote rm origin
	git remote add origin https://github.com/$($settings.github_username)/$($modObject.NameClean)
	git fetch
	git checkout $newBranch
	git pull origin $newBranch
	git rm -rf *
	git commit -S -m "Deleted obsolete files"
	git merge master-holder --allow-unrelated-histories
	git push origin $newBranch
	git push --tags

	$applicationPath = $settings.browser_path
	$arguments = "https://github.com/$($settings.github_username)/$($modObject.NameClean)/tags"
	Start-Process -FilePath $applicationPath -ArgumentList $arguments
	Get-ZipFile -modObject $modObject -filename "$($modObject.NameClean)_$newVersion.zip"
	Move-Item "$($modObject.ModFolderPath)\$($modObject.NameClean)_$newVersion.zip" "$stagingDirectory\$($modObject.NameClean)_$newVersion.zip"
	Remove-Item .\debug.log -Force -ErrorAction SilentlyContinue
	ReadHost "Waiting for zip to be uploaded from $stagingDirectory, continue when done (Press ENTER)"
	Remove-Item "$stagingDirectory\$($modObject.NameClean)_$newVersion.zip" -Force
	Write-Progress -Completed

	Set-Location $currentDirectory
	Set-DefaultGithubRepoValues -modObject $modObject
	Set-Clipboard "$($modObject.ModFolderPath)\About\Preview.png"
	Start-Process -FilePath $settings.browser_path -ArgumentList "https://github.com/$($settings.github_username)/$($modObject.NameClean)/settings"
}

function Set-DefaultGithubRepoValues {
	param (
		$modObject
	)
	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not (Get-RepositoryStatus -repositoryName $modObject.NameClean)) {
		WriteMessage -failure "Repository $($modObject.NameClean) does not exist"
		return
	}

	WriteMessage -progress "Verifying default github values for $($modObject.NameClean)"

	$currentLocation = Get-Location
	Set-Location $modObject.ModFolderPath
	git maintenance start
	Set-Location $currentLocation

	$currentValues = Get-GithubRepoInfo -repoName $modObject.NameClean

	$repoData = @{}

	if ($currentValues.has_wiki) {
		$repoData["has_wiki"] = $false
	}
	if ($currentValues.has_pages) {
		$repoData["has_pages"] = $false
	}
	if ($currentValues.has_discussions) {
		$repoData["has_discussions"] = $false
	}
	if ($currentValues.has_projects) {
		$repoData["has_projects"] = $false
	}
	if (-not $currentValues.has_issues) {
		$repoData["has_issues"] = $true
	}
	$description = "Repository for the Rimworld mod named $($modObject.DisplayName)"
	if ($currentValues.description -ne $description) {
		$repoData["description"] = $description
	}
	if ($currentValues.homepage -ne $modObject.ModUrl) {
		$repoData["homepage"] = $modObject.ModUrl
	}

	if ($repoData.Count -gt 0) {
		WriteMessage -message "Updating default values for repository $($modObject.NameClean)" -progress
		$repoParams = @{
			Uri         = "https://api.github.com/repos/$($settings.github_username)/$($modObject.NameClean)";
			Method      = 'PATCH';
			Headers     = @{
				Authorization = 'Basic ' + [Convert]::ToBase64String(
					[Text.Encoding]::ASCII.GetBytes($settings.github_api_token + ":x-oauth-basic"));
			}
			ContentType = 'application/json';
			Body        = (ConvertTo-Json $repoData -Compress)
		}
		Invoke-RestMethod @repoParams | Out-Null
	}

	$topics = @("gaming", "modding", "rimworld")
	if ($modObject.HasXml) {
		$topics += "xml"
	}
	if ($modObject.HasAssemblies) {
		$topics += "csharp"
	}
	if ($currentValues.topics.Count -ne $topics.Count) {
		WriteMessage -message "Updating topics for repository $($modObject.NameClean)" -progress

		$repoData = @{
			"names" = $topics
		}
		$repoParams = @{
			Uri         = "https://api.github.com/repos/$($settings.github_username)/$($modObject.NameClean)/topics";
			Method      = 'PUT';
			Headers     = @{
				Authorization = 'Basic ' + [Convert]::ToBase64String(
					[Text.Encoding]::ASCII.GetBytes($settings.github_api_token + ":x-oauth-basic"));
			}
			ContentType = 'application/json';
			Body        = (ConvertTo-Json $repoData -Compress)
		}
		Invoke-RestMethod @repoParams | Out-Null

		$repoData.topics = $topics
	}

	if (-not (Get-GitSubscriptionStatus -repoName $modObject.NameClean)) {
		WriteMessage -message "Updating subscription for repository $($modObject.NameClean)" -progress
		Set-GitSubscriptionStatus -repoName $modObject.NameClean -enabled $true | Out-Null
	}
	Set-GithubIssueWebhook -repoName $modObject.NameClean
	WriteMessage -progress "Done"
}


#endregion

#region File-functions

# Generates a new ModSync-file for a mod
function New-ModSyncFile {
	param (
		$modObject,
		$version
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}
	if (-not (Test-Path $modSyncTemplate)) {
		WriteMessage -failure "Cound not find ModSync-template: $($modSyncTemplate), skipping."
		return
	}
	$targetPath = $modObject.ModSyncFilePath
	Copy-Item $modSyncTemplate $targetPath -Force
	((Get-Content -path $targetPath -Raw -Encoding UTF8).Replace("[guid]", [guid]::NewGuid().ToString())) | Set-Content -Path $modObject.ModSyncFilePath
	((Get-Content -path $targetPath -Raw -Encoding UTF8).Replace("[modname]", $modObject.DisplayName)) | Set-Content -Path $modObject.ModSyncFilePath
	((Get-Content -path $targetPath -Raw -Encoding UTF8).Replace("[version]", $version)) | Set-Content -Path $modObject.ModSyncFilePath
	((Get-Content -path $targetPath -Raw -Encoding UTF8).Replace("[username]", $settings.github_username)) | Set-Content -Path $modObject.ModSyncFilePath
	((Get-Content -path $targetPath -Raw -Encoding UTF8).Replace("[modwebpath]", $modObject.NameClean)) | Set-Content -Path $modObject.ModSyncFilePath
}

# Texturename function
# Checks for textures with the old naming-style (side/front/back) and replaces it
# with the new style (east/south/north)
function Update-Textures {
	param(
		$modObject
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not $modObject.ModFolderPath) {
		WriteMessage -failure "Folder for $($modObject.Name) can not be found, exiting"
		return
	}
	if (-not $modObject.Mine) {
		WriteMessage -failure "$($modObject.Name) is not mine, aborting update"
		return
	}
	Set-Location $modObject.ModFolderPath
	$files = Get-ChildItem . -Recurse
	foreach ($file in $files) {
		if (-not $file.FullName.Contains("Textures")) {
			continue
		}
		if ($file.Extension -eq ".psd") {
			Move-Item $file.FullName "$($modObject.ModFolderPath)\Source\" -Force -Confirm:$false | Out-Null
			continue
		}
		$newName = $file.Name.Replace("_side", "_east").Replace("_Side", "_east").Replace("_front", "_south").Replace("_Front", "_south").Replace("_back", "_north").Replace("_Back", "_north").Replace("_rear", "_north").Replace("_Rear", "_north")
		$newPath = $file.FullName.Replace($file.Name, $newName)
		Move-Item $file.FullName "$newPath" -ErrorAction SilentlyContinue | Out-Null
	}
	Write-Progress -Completed
}


# Adds an update post to the mod
# If HugsLib is loaded this will be shown if new to user
# Also generates a Tabula Rasa update message of the same type
function Set-ModUpdateFeatures {
	param (
		$modObject,
		[string] $updateMessage,
		[switch] $Force
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not $Force -and -not $modObject.Mine) {
		WriteMessage -failure "$($modObject.Name) is not mine, aborting update"
		return
	}
	if (-not $updateMessage) {
		$news = Get-MultilineMessage -query "Add update-message?"
		if (-not $news) {
			return
		}
	} else {
		$news = $updateMessage
	}

	$updatefeaturesFileName = Split-Path $updatefeaturesTemplate -Leaf
	$updateinfoFileName = Split-Path $updateinfoTemplate -Leaf

	$updateFeaturesPath = "$($modObject.ModFolderPath)\News\$updatefeaturesFileName"
	$updateFeaturesFolder = Split-Path $updateFeaturesPath
	$updateinfoPath = "$($modObject.ModFolderPath)\$($modObject.HighestSupportedVersion)\Defs\$updateinfoFileName"
	if (-not (Test-Path "$($modObject.ModFolderPath)\$($modObject.HighestSupportedVersion)")) {
		$updateinfoPath = "$($modObject.ModFolderPath)\Defs\$updateinfoFileName"
	}
	$updateinfoFolder = Split-Path $updateinfoPath

	if (-not (Test-Path $updateFeaturesFolder)) {
		New-Item -Path $updateFeaturesFolder -ItemType Directory -Force | Out-Null
	}
	if (-not (Test-Path $updateinfoFolder)) {
		New-Item -Path $updateinfoFolder -ItemType Directory -Force | Out-Null
	}
	if (-not (Test-Path $updateFeaturesPath)) {
		(Get-Content -Path $updatefeaturesTemplate -Raw -Encoding UTF8).Replace("[modname]", $modObject.Name).Replace("[modid]", $modObject.PublishedId) | Out-File $updateFeaturesPath
	}
	if (-not (Test-Path $updateinfoPath)) {
		(Get-Content -Path $updateinfoTemplate -Raw -Encoding UTF8).Replace("[modname]", $modObject.Name).Replace("[modid]", $modObject.PublishedId) | Out-File $updateinfoPath
	}
	Update-InfoBanner -modObject $modObject

	$version = $modObject.ManifestFileXml.Manifest.version
	$defName = "$($modObject.Name.Replace(" ", "_"))_$($version.Replace(".", "_"))"
	$newsObject = "	<HugsLib.UpdateFeatureDef ParentName=""$($modObject.Name)_UpdateFeatureBase"">
		<defName>$defName</defName>
		<assemblyVersion>$version</assemblyVersion>
		<content>$news</content>
	</HugsLib.UpdateFeatureDef>
</Defs>"
	(Get-Content -Path $updateFeaturesPath -Raw -Encoding UTF8).Replace("</Defs>", $newsObject) | Out-File $updateFeaturesPath

	$dateString = "$((Get-Date).Year)/$((Get-Date).Month)/$((Get-Date).Day)"
	$infoObject = "	<TabulaRasa.UpdateDef ParentName=""$($modObject.Name)_UpdateInfoBase"" MayRequire=""neronix17.toolbox"">
		<defName>$defName</defName>
		<date>$dateString</date>
		<content>$news</content>
	</TabulaRasa.UpdateDef>
</Defs>"
	(Get-Content -Path $updateinfoPath -Raw -Encoding UTF8).Replace("</Defs>", $infoObject) | Out-File $updateinfoPath

	WriteMessage -success "Added update news for $($modObject.Name)"
}


# Adds an changelog post to the mod
function Set-ModChangeNote {
	param (
		$modObject,
		[string] $changenote,
		[switch] $Force
	)
	if (-not $Force -and -not $modObject.Mine) {
		WriteMessage -failure "$($modObject.Name) is not mine, aborting update"
		return
	}
	$baseLine = "# Changelog for $($modObject.Name)"
	if (-not $modObject.ChangelogPath) {
		$modObject.ChangelogPath = "$($modObject.ModFolderPath)\About\Changelog.txt"
		$baseLine  | Out-File $modObject.ChangelogPath
	}

	$replaceLine = "$baseLine

$Changenote
"
	(Get-Content -Path $modObject.ChangelogPath -Raw -Encoding UTF8).Replace($baseLine, $replaceLine) | Out-File $modObject.ChangelogPath -NoNewline
	WriteMessage -success "Added changelog for $($modObject.Name)"
	return
}

# Restructures a mod-folder to use the correct structure
function Set-CorrectFolderStructure {
	param(
		$modObject
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not $modObject.Mine) {
		WriteMessage -failure "$($modObject.Name) is not mine, aborting update"
		return
	}

	if (-not $modObject.AboutFilePath) {
		WriteMessage -warning "No about-file for $($modObject.Name)"
		return
	}
	if (-not $modObject.Published) {
		WriteMessage -warning  "$($modObject.Name) is not published"
		return
	}
	if ($modObject.LoadFoldersPath) {
		WriteMessage -warning "$($modObject.Name) has a LoadFolder.xml, will not change folders"
		return
	}

	$missingVersionFolders = @()
	$subfolderNames = @()
	foreach	($version in $modObject.SupportedVersions) {
		if (Test-Path "$($modObject.ModFolderPath)\$version") {
			$childFolders = Get-ChildItem "$($modObject.ModFolderPath)\$version" -Directory
			foreach ($folder in $childFolders) {
				if ($subfolderNames.Contains($folder.Name)) {
					continue
				}
				$subfolderNames += $folder.Name
			}
		} else {
			$missingVersionFolders += $version
		}
	}
	if ($missingVersionFolders.Length -eq 0 -or $missingVersionFolders.Length -eq $currentVersions.Length) {
		WriteMessage -success "$($modObject.Name) has correct folder structure"
		return
	}
	if ($missingVersionFolders.Length -gt 1) {
		WriteMessage -warning "$($modObject.Name) has $($missingVersionFolders.Length) missing version-folders, cannot fix automatically"
		return
	}
	WriteMessage -progress "$($modObject.Name) has missing version-folder: $($missingVersionFolders -join ",")"
	WriteMessage -progress "Will move the following folders to missing version-folder: $($subfolderNames -join ",")"
	foreach ($missingVersionFolder in $missingVersionFolders) {
		New-Item -Path "$($modObject.ModFolderPath)\$missingVersionFolder" -ItemType Directory -Force | Out-Null
		foreach ($subfolderName in $subfolderNames) {
			if (Test-Path "$($modObject.ModFolderPath)\$subfolderName") {
				Move-Item -Path "$($modObject.ModFolderPath)\$subfolderName" -Destination "$($modObject.ModFolderPath)\$missingVersionFolder\$subfolderName" -Force | Out-Null
			} else {
				WriteMessage -progress "$($modObject.ModFolderPath)\$subfolderName doeas not exist, version-specific folder"
			}
		}
		Write-Progress -Completed
	}
	WriteMessage -success "$($modObject.Name) has correct folder structure"
}

# Jumps to a mod-folder
function Get-LocalModFolder {
	param(
		$modName,
		$repoName
	)

	if ($repoName) {
		$modName = $repoName.Replace("+", "Plus")
	}
	$targetPath = "$localModFolder\$modName"
	if (-not (Test-Path $targetPath)) {
		WriteMessage -failure "Could not find $targetPath"
		return $false
	}
	Set-Location $targetPath
	return $true
}


# Main mod-updating function
# Goes through all xml-files from current directory and replaces old strings/properties/valuenames.
# Can be run with the -Test parameter to just return a report of stuff that need updating, this can
# be useful to run first when starting with a mod update to see if there is a need for creating a
# separate 1.1-folder.
function Update-Defs {
	param(
		$modObject,
		[switch]$Test
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not $modObject.ModFolderPath) {
		WriteMessage -failure "No folder found for $($modObject.Name)"
		return
	}

	$files = Get-ChildItem "$($modObject.ModFolderPath)\*.xml" -Recurse
	$replacements = Get-Content $replacementsFile -Encoding UTF8
	$infoBlob = ""
	$count = 1
	foreach ($file in $files) {
		SetTerminalProgress -progressPercent ($count / $files.Count * 100)
		$count++
		$fileContent = Get-Content -path $file.FullName -Raw -Encoding UTF8
		if (-not $fileContent.StartsWith("<?xml")) {
			$fileContent = "<?xml version=""1.0"" encoding=""utf-8""?>" + $fileContent
		}
		$xmlRemove = @()
		$output = ""
		$localInfo = ""
		foreach ($row in $replacements) {
			if ($row.Length -eq 0) {
				continue
			}
			if ($row.StartsWith("#")) {
				continue
			}
			$type = $row.Split("|")[0]
			$searchText = $row.Split("|")[1]
			if ($row.Split("|").Length -eq 3) {
				$replaceText = $row.Split("|")[2]
			} else {
				$replaceText = ""
			}
			if ($type -eq "p" -or $type -eq "pi") {
				# Property
				$exists = $fileContent | Select-String -Pattern "<$searchText>" -AllMatches -CaseSensitive
				if ($exists.Matches.Count -eq 0) {
					continue
				}
				if ($type -eq "pi") {
					$localInfo += "`n$($exists.Matches.Count): INFO PROPERTY $searchText - $replaceText"
					continue
				}
				if ($replaceText.Length -gt 0) {
					$output += "`n$($exists.Matches.Count): REPLACE PROPERTY $searchText WITH $replaceText"
				} else {
					$output += "`n$($exists.Matches.Count): REMOVE PROPERTY $searchText"
				}
				if ($Test) {
					continue
				}
				if ($replaceText.Length -gt 0) {
					$fileContent = $fileContent.Replace("<$searchText>", "<$replaceText>").Replace("</$searchText>", "</$replaceText>")
				} else {
					$xmlRemove += $searchText
				}
				continue
			}
			if ($type -eq "v" -or $type -eq "vi") {
				# Value
				$exists = $fileContent | Select-String -Pattern ">$searchText<" -AllMatches -CaseSensitive
				if ($exists.Matches.Count -eq 0) {
					continue
				}
				if ($type -eq "vi") {
					$localInfo += "`n$($exists.Matches.Count): INFO VALUE $searchText - $replaceText"
					continue
				}
				$output += "`n$($exists.Matches.Count): REPLACE VALUE $searchText WITH $replaceText"
				if ($Test) {
					continue
				}
				$fileContent = $fileContent.Replace(">$searchText<", ">$replaceText<")
				continue
			}
			if ($type -eq "s" -or $type -eq "si") {
				#String
				$exists = $fileContent | Select-String -Pattern "$searchText" -AllMatches -CaseSensitive
				if ($exists.Matches.Count -eq 0) {
					continue
				}
				if ($type -eq "si") {
					$localInfo += "`n$($exists.Matches.Count): INFO STRING $searchText - $replaceText"
					continue
				}
				$output += "`n$($exists.Matches.Count): REPLACE STRING $searchText WITH $replaceText"
				if ($Test) {
					continue
				}
				$fileContent = $fileContent.Replace($searchText, $replaceText)
				continue
			}
		}
		if ($output) {
			Write-Host "$($file.BaseName)`n$output`n"
		}
		try {
			[xml]$xmlContent = $fileContent
		} catch {
			"`n$($file.FullName) could not be read as xml."
			WriteMessage -failure $_
			$applicationPath = $settings.text_editor_path
			$arguments = """$($file.FullName)"""
			Start-Process -FilePath $applicationPath -ArgumentList $arguments
			continue
		}
		$firstNode = $xmlContent.ChildNodes[1]
		if ($firstNode.Name -ne "Defs" -and $file.FullName.Contains("\Defs\")) {
			$output += "`nREPLACE $($firstNode.Name) WITH Defs"
			$newNode = $xmlContent.CreateElement('Defs')
			while ($null -ne $firstNode.FirstChild) {
				[void]$newNode.AppendChild($firstNode.FirstChild)
			}
			[void]$xmlContent.RemoveChild($firstNode)
			[void]$xmlContent.AppendChild($newNode)
		}
		if ($localInfo -ne "") {
			$infoBlob += "$($file.BaseName)`n$localInfo`n"
		}
		if ($Test) {
			continue
		}
		foreach ($property in $xmlRemove) {
			if ($fileContent -match "<$property>") {
				$xmlContent.SelectNodes("//$property") | ForEach-Object { $_.ParentNode.RemoveChild($_) } | Out-Null
			}
		}
		$xmlContent.Save($file.FullName)
	}
	SetTerminalProgress
	if ($infoBlob -ne "") {
		Write-Host $infoBlob.Replace("#n", "`n")
	}
}


# XML-cleaning function
# Resaves all XML-files using validated XML. Also warns if there seems to be overwritten base-defs
# Useful to run on a mod to remove all extra whitespaces and redundant formatting
function Set-ModXml {
	[CmdletBinding()]
	param(
		$modObject,
		[switch]$allFiles,
		[switch]$doBaseCheck)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return $false
		}
	}

	if ($allFiles -or -not $modObject.MetadataFileJson.LastXmlCleaning) {
		$fromDate = (Get-Date).AddDays(-1000)
	} else {
		$fromDate = [datetime]::Parse($modObject.MetadataFileJson.LastXmlCleaning)
	}

	# Clean up XML-files
	$files = Get-ChildItem "$($modObject.ModFolderPath)\*.xml" -Recurse | Where-Object { $_.LastWriteTime -gt $fromDate }
	$total = $files.Count
	if ($total -eq 0) {
		WriteMessage -progress "No XML-files changed since $($fromDate.ToShortDateString())"
		return $true
	} else {
		WriteMessage -progress "Found $total changed XML-files"
	}
	$tempFile = "$env:TEMP\temp.xml"
	$filesChanged = 0;

	$progressObject = WriteProgress -initiate -title "Cleaning up XML-files" -totalActions $total

	foreach ($file in $files) {
		WriteProgress -progressObject $progressObject
		Write-Verbose "Checking $($file.FullName.Replace($modObject.ModFolderPath, ''))"
		$fileContentRaw = Get-Content -path $file.FullName -Raw -Encoding UTF8
		if (-not $fileContentRaw.StartsWith("<?xml")) {
			$fileContentRaw = "<?xml version=""1.0"" encoding=""utf-8""?>" + $fileContentRaw
		}
		try {
			[xml]$fileContent = $fileContentRaw
		} catch {
			"`n$($file.FullName) could not be read as xml."
			WriteMessage -failure $_
			$applicationPath = $settings.text_editor_path
			$arguments = """$($file.FullName)"""
			Start-Process -FilePath $applicationPath -ArgumentList $arguments
			WriteProgress -progressObject $progressObject -finished
			return $false
		}
		if (-not $doBaseCheck) {
			$fileContent.Save($tempFile)
			(Get-Content -path $tempFile -Raw -Encoding UTF8).Replace('&gt;', '>') | Set-Content -Path $tempFile -Encoding UTF8
			if ((Get-Content -path $tempFile -Raw -Encoding UTF8) -ne $fileContentRaw) {
				Copy-Item -Path $tempFile -Destination $file.FullName -Force
				$filesChanged++
			}
			continue
		}
		$allBases = $fileContent.Defs.ChildNodes | Where-Object -Property Name -Match "Base$"
		$baseWarnings = @()
		foreach ($def in $allBases) {
			if ($null -eq $def.ParentName -and $def.Abstract -eq $true) {
				$baseWarnings += $def.Name
			}
		}
		if ($baseWarnings.Count -gt 0) {
			$applicationPath = $settings.text_editor_path
			$arguments = """$($file.FullName)"""
			Start-Process -FilePath $applicationPath -ArgumentList $arguments
			Write-Host "`n$($file.FullName)"
			WriteMessage -warning "Possible redundant base-classes: $($baseWarnings -join ", ")"
		}
		$fileContent.Save($tempFile)
		(Get-Content -path $tempFile -Raw -Encoding UTF8).Replace('&gt;', '>') | Set-Content -Path $tempFile -Encoding UTF8
		if ((Get-Content -path $tempFile -Raw -Encoding UTF8) -ne $fileContentRaw) {
			Copy-Item -Path $tempFile -Destination $file.FullName -Force
			$filesChanged++
		}
	}
	WriteProgress -progressObject $progressObject -finished
	Set-LastXmlCleaning -modObject $modObject
	if ($filesChanged -eq 0) {
		WriteMessage -progress "No XML-files needed cleaning"
	} else {
		WriteMessage -success "Cleaned up $filesChanged XML-files"
	}
	return $true
}


# Generates a zip-file of a mod, looking in the _PublisherPlus.xml for exlusions
function Get-ZipFile {
	param(
		$modObject,
		$fileName
	)

	$exclusionsToAdd = " -xr!""_PublisherPlus.xml"""
	if ($modObject.ModPublisherPath) {
		foreach ($exclusion in ([xml](Get-Content $modObject.ModPublisherPath -Raw -Encoding UTF8)).Configuration.Excluded.exclude) {
			$niceExclusion = $exclusion.Replace("$($modObject.ModFolderPath)\", "")
			$exclusionsToAdd += " -xr!""$niceExclusion"""
		}
	}
	$outFile = "$($modObject.ModFolderPath)\$filename"
	$7zipPath = $settings.zip_path
	$arguments = "a ""$outFile"" ""$($modObject.ModFolderPath)"" -r -mx=9 -mmt=10 -bd $exclusionsToAdd "
	Start-Process -FilePath $7zipPath -ArgumentList $arguments -Wait -NoNewWindow
}

# Fetches a mod and saves it to a zip-file
function Get-SteamModContent {
	param (
		$modId,
		$savePath,
		[switch]$overwrite
	)

	if (-not $overwrite -and (Test-Path $savePath)) {
		WriteMessage -failure "$savePath already exists, will not download"
		return $false
	}

	if (-not $savePath.EndsWith(".zip")) {
		WriteMessage -failure "$savePath must end with .zip"
		return $false
	}

	if (-not (Get-ModInfo -steamIds $modId).Exists) {
		WriteMessage -failure "$modId is not working"
		return $false
	}

	$modContentPath = "$localModFolder\..\..\..\workshop\content\294100\$modId"
	$subscribed = Test-Path "$modContentPath\About\About.xml"
	if (-not $subscribed) {
		Set-ModSubscription -modId $modId -subscribe $true | Out-Null
	}

	$tempPath = "$env:TEMP\ModDownloadFolder"
	if (Test-Path $tempPath) {
		Remove-Item -Path $tempPath -Recurse -Force -Confirm:$false
	}
	New-Item $tempPath -ItemType Directory | Out-Null

	Copy-Item -Path "$modContentPath\*" -Destination $tempPath -Recurse

	New-Item "$tempPath\Steampage" -ItemType Directory | Out-Null

	Get-ModDescription -modId $modId | Out-File "$tempPath\Steampage\PublishedDescription.txt" -Force -Encoding utf8

	$imageLinks = Select-String -Path "$tempPath\Steampage\PublishedDescription.txt" -Pattern "\[img\].*\[\/img\]" -AllMatches
	if ($imageLinks) {
		$i = 0
		foreach ($link in $imageLinks.Matches.Value) {
			$linkValue = $link.Split("]")[1].Split("[")[0].Split("?")[0]
			if ($linkValue -match "steamuserimages-a") {
				$fileName = "image_$i.jpg"
			} else {
				$fileName = Split-Path -Leaf $linkValue
			}
			$ProgressPreference = 'SilentlyContinue'
			Invoke-WebRequest $linkValue -OutFile "$tempPath\Steampage\$fileName" | Out-Null
			$ProgressPreference = 'Continue'
			$i++
		}
	}

	$7zipPath = $settings.zip_path
	$arguments = "a ""$savePath"" ""$tempPath\*"" -r -mx=9 -mmt=10 -bd -bb0"
	Start-Process -FilePath $7zipPath -ArgumentList $arguments -Wait -NoNewWindow | Out-Null

	if (-not $subscribed) {
		Set-ModSubscription -modId $modId -subscribe $false	| Out-Null
	}

	return $true
}

function Update-ModEggDefs {
	[CmdletBinding()]
	param(
		$folderPath
	)
	if (-not (Test-Path $folderPath)) {
		WriteMessage -failure "Folder $folderPath does not exist, exiting"
		return
	}

	$files = Get-ChildItem -Path $folderPath -Filter "*.xml" -Recurse

	foreach ($filePath in $files) {

		try {

			[xml]$xml = Get-Content $filePath

			# Update egg layer definitions
			$eggLayerNodes = $xml.SelectNodes("//li[@Class='CompProperties_EggLayer']")

			if ($eggLayerNodes -and $eggLayerNodes.Count -gt 0) {
				foreach ($eggLayer in $eggLayerNodes) {
					$fertNode = $eggLayer.SelectSingleNode("eggFertilizedDef")
					$unfertNode = $eggLayer.SelectSingleNode("eggUnfertilizedDef")

					if ($fertNode -and -not $unfertNode) {
						# Generate unfertilized def name
						$fertDefName = $fertNode.InnerText
						$unfertDefName = $fertDefName -replace "EggFertilized$", "EggUnFertilized"

						# Create new node
						$newUnfertNode = $xml.CreateElement("eggUnfertilizedDef")
						$newUnfertNode.InnerText = $unfertDefName

						# Insert after fertilized node
						$null = $eggLayer.InsertAfter($newUnfertNode, $fertNode)
					}
				}
				WriteMessage -success "Updated egg layer definitions in $($filePath.FullName)"
				$xml.Save($filePath.FullName)
				[xml]$xml = Get-Content $filePath
			}

			$thingDefs = $xml.SelectNodes("//ThingDef[@ParentName='EggFertBase']")
			$unfertThings = $xml.SelectNodes("//ThingDef[@ParentName='EggUnfertBase']")

			if ( -not $thingDefs -or $thingDefs.Count -eq 0) {
				continue
			}

			# Build a list of existing unfertilized defNames for quick lookup

			$existingUnfertDefNames = @{}
			Write-Verbose "Checking existing unfertilized egg definitions"
			foreach ($unfert in $unfertThings) {
				$defNameNode = $unfert.SelectSingleNode("defName")
				if ($defNameNode) {
					$existingUnfertDefNames[$defNameNode.InnerText] = $true
				}
			}

			foreach ($def in $thingDefs) {
				Write-Verbose "Starting processing for $($def.defName)"
				$fertDefName = $def.defName

				if ( -not $fertDefName -or -not $fertDefName.EndsWith("EggFertilized")) {
					Write-Verbose "Skipping $fertDefName as it does not end with 'EggFertilized'"
					continue
				}

				$unfertDefName = $fertDefName -replace "EggFertilized$", "EggUnFertilized"

				# Skip if unfertilized version already exists
				if ($existingUnfertDefNames.ContainsKey($unfertDefName)) {
					Write-Verbose "Skipping $fertDefName as unfertilized version $unfertDefName already exists"
					continue
				}

				$newDef = $def.Clone()

				# Change ParentName
				$newDef.ParentName = "EggUnfertBase"

				# Modify defName
				$newDef.defName = $unfertDefName

				# Modify label
				Write-Verbose "Modifying label for $fertDefName to $unfertDefName"
				$labelNode = $newDef.SelectSingleNode("label")
				if ($labelNode) {
					$labelNode.InnerText = $labelNode.InnerText -replace "\(fert\.\)", "(unfert.)"
				}

				# Modify description
				Write-Verbose "Modifying description for $fertDefName to $unfertDefName"
				$descText = $newDef.description
				$descText = "An unfertilized" + (($descText -replace "^A natural", "") -replace "^A fertilized", "") -replace "With enough care.*?[\.\!]", ""
				$newDef.description = $descText.Trim()

				# Modify MarketValue
				Write-Verbose "Modifying MarketValue for $fertDefName to half"
				$marketValueNode = $newDef.SelectSingleNode("statBases/MarketValue")
				if ($marketValueNode) {
					$marketValueNode.InnerText = [math]::Round([double]$marketValueNode.InnerText * 0.5, 2)
				}

				# Remove comps node
				Write-Verbose "Removing comps node from $fertDefName"
				$compsNode = $newDef.SelectSingleNode("comps")
				if ($compsNode) {
					$null = $newDef.RemoveChild($compsNode)
				}

				# Insert after original
				$parent = $def.ParentNode
				$null = $parent.InsertAfter($newDef, $def)
			}

			# Save the modified XML
			$xml.Save($filePath.FullName)
			WriteMessage -success "Updated egg definitions in $($filePath.FullName)"
		} catch {
			Write-Error "Error processing file '$($filePath.FullName)': $_"
			throw
		}

	}
}


function Update-ModWildness {
	param(
		$folderPath
	)

	if (-not (Test-Path $folderPath)) {
		WriteMessage -failure "Folder $folderPath does not exist, exiting"
		return
	}

	$files = Get-ChildItem -Path $folderPath -Filter "*.xml" -Recurse

	foreach ($filePath in $files) {
		# Load the XML content
		[xml]$xml = Get-Content $filePath

		# Find all <ThingDef> nodes
		foreach ($thingDef in $xml.Defs.ThingDef) {
			# Locate the <wildness> element inside <race> (Ensure it's treated as an XmlNode)
			$wildnessNode = $thingDef.race ? $thingDef.race.SelectSingleNode("wildness") : $null

			if (-not $wildnessNode) {
				continue
			}

			# Find or create the <statBases> node
			if ($null -eq $thingDef.statBases) {
				$thingDef.AppendChild($xml.CreateElement("statBases")) | Out-Null
			}

			$statBasesNode = $thingDef.SelectSingleNode("statBases")
			if (-not $statBasesNode) {
				$statBasesNode = $xml.CreateElement("statBases")
				$thingDef.AppendChild($statBasesNode) | Out-Null
			}


			# Create a new <Wildness> element and transfer the value
			$newWildnessNode = $xml.CreateElement("Wildness")
			$newWildnessNode.InnerText = $wildnessNode.InnerText

			# Add <Wildness> to <statBases>
			$statBasesNode.AppendChild($newWildnessNode) | Out-Null

			# Remove the original <wildness> node (This time, using the correct reference)
			$thingDef.race.RemoveChild($wildnessNode)
		}

		# Save the modified XML back to the file
		$xml.Save($filePath)
	}
	WriteMessage -success "Updated wildness in all XML files in $folderPath"
}

#endregion

#region Get-info functions

# Easy load of a mods steam-page
# Gets the published ID for a mod and then opens it in the selected browser
function Get-ModPage {
	param(
		$modObject,
		[string]$modName,
		[switch]$getLink
	)
	if (-not $modName -and -not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	} elseif (-not $modObject) {
		$modObject = Get-Mod -modName $modName
		if (-not $modObject) {
			return
		}
	}

	if (-not $modObject.ModUrl) {
		WriteMessage -failure "Mod has no url registered"
		return
	}
	$arguments = $modObject.ModUrl
	if ($getLink) {
		return $arguments
	}
	$applicationPath = $settings.browser_path
	Start-Process -FilePath $applicationPath -ArgumentList $arguments
	Start-Sleep -Seconds 1
	Remove-Item "$($modObject.ModFolderPath)\debug.log" -Force -ErrorAction SilentlyContinue
}

# Gets the modname from the current location
function Get-CurrentModNameFromLocation {
	$currentDirectory = (Get-Location).Path
	if (-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
		WriteMessage -failure "Can only be run from somewhere under $localModFolder, exiting"
		return
	}
	return $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
}

# Returns true if the mod supports the latest game-version
function Get-ModSteamStatus {
	[CmdletBinding()]
	param (
		$modObject,
		$modLink
	)

	if ($modLink) {
		$modVersions = (Get-ModInfo -steamIds $modLink.Split("=")[1]).Tags
	} else {
		if (-not $modObject) {
			$modObject = Get-Mod
			if (-not $modObject) {
				return
			}
		}
		$modVersions = (Get-ModInfo -steamIds $modObject.PublishedId).Tags
	}

	$currentVersionString = Get-CurrentRimworldVersion

	if (-not $modVersions) {
		Write-Verbose "Can not find mod on Steam. Modname: $($modObject.Name), ModLink: $modLink, exiting"
		return $false
	}

	Write-Verbose "Found mod-versions on steam: $modversions, and current game-version is $currentVersionString"
	if ($modVersions -match $currentVersionString) {
		return $true
	}
	return $false
}

# Returns an array of all mod-directories of mods by a specific author
function Get-AllModsFromAuthor {
	param (
		[string]$author,
		[switch]$onlyPublished
	)
	$allMods = Get-ChildItem -Directory $localModFolder
	$returnArray = @()
	$progressObject = WriteProgress -initiate -title "Seraching mod-folders for mods by $author" -totalActions $allMods.Count
	foreach ($folder in $allMods) {
		WriteProgress -progressObject $progressObject
		$modObject = Get-Mod -modName $folder.Name

		if (-not $modObject.AboutFilePath) {
			continue
		}
		if ($onlyPublished -and -not $modObject.Published) {
			continue
		}
		if ($modObject.Author -eq $author) {
			$returnArray += $folder.Name
		}
	}
	WriteProgress -progressObject $progressObject -finished
	return $returnArray
}

# Returns a list of all mods where files have been modified since the last publish.
function Get-AllNonPublishedMods {
	param (
		[switch]$detailed,
		[switch]$ignoreAbout
	)
	$allMods = Get-ChildItem -Directory $localModFolder
	$returnArray = @()
	$progressObject = WriteProgress -initiate -title "Searching for all Non-published mods" -totalActions $allMods.Count
	foreach ($folder in $allMods) {
		WriteProgress -progressObject $progressObject
		$modObject = Get-Mod -modName $folder.Name
		if (-not $modObject.ModSyncFilePath) {
			continue
		}
		if (-not $modObject.Published) {
			continue
		}
		$modsyncFileModified = (Get-Item $modObject.ModSyncFilePath).LastWriteTime

		if ($ignoreAbout) {
			$newerFiles = Get-ChildItem $folder.FullName -File -Recurse -Exclude "About.xml" | Where-Object { $_.LastWriteTime -gt $modsyncFileModified.AddMinutes(5) }
		} else {
			$newerFiles = Get-ChildItem $folder.FullName -File -Recurse  | Where-Object { $_.LastWriteTime -gt $modsyncFileModified.AddMinutes(5) }
		}
		if ($newerFiles.Count -gt 0) {
			$returnString = "`n$($modObject.Name) has $($newerFiles.Count) files newer than publish-date"
			if ($detailed) {
				$returnString += ":"
				foreach ($file in $newerFiles) {
					$minutesString = "$([math]::floor(($file.LastWriteTime - $modsyncFileModified).TotalMinutes)) minutes newer"
					$returnString += "`n$($file.FullName.Replace($localModFolder, '').Replace('\$($folder.Name)', '')) - $minutesString"
				}
			}
			$returnArray += $returnString
		}
	}
	WriteProgress -progressObject $progressObject -finished
	return $returnArray
}

function Test-ValidIdentifier {
	param (
		[string]$identifier
	)
	$identifier = $identifier.ToLower()
	if ($identifier.Contains(" ")) {
		WriteMessage -warning "Identifier $identifier contains spaces"
		return $false
	}
	if (-not $identifier.Contains(".")) {
		WriteMessage -warning "Identifier $identifier is missing dots"
		return $false
	}
	if ($identifier -eq "brrainz.harmony") {
		return $false
	}
	if ($identifier.StartsWith("ludeon.")) {
		return $false
	}
	return $true
}

# Scans a mods About-file for mod-identifiers and returns an array of them, with the selected mods identifier last
function Get-IdentifiersFromMod {
	[CmdletBinding()]
	param (
		$modObject,
		[string]$modId,
		[switch]$oldmod,
		[switch]$alsoLoadBefore,
		[string]$modFolderPath,
		$gameVersion,
		[switch]$bare
	)

	if ($modId) {
		if ($modId.StartsWith("Mlie.")) {
			$modObject = Get-Mod -modName $modId.Replace("Mlie.", "")
		} else {
			if (-not (Test-Path "$localModFolder\..\..\..\workshop\content\294100\$modId")) {
				WriteMessage -progress "Could not find mod with id $modId, subscribing"
				Set-ModSubscription -modId $modId -subscribe $true | Out-Null
			}
			$modObject = Get-Mod -modPath "$localModFolder\..\..\..\workshop\content\294100\$modId"
		}
	}
	if ($modFolderPath) {
		$modObject = Get-Mod -modPath $modFolderPath
	}

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return $false
		}
	}

	if (-not $modObject.AboutFilePath) {
		WriteMessage -failure "Could not find About-file for mod. Name: $($modObject.Name) |Modid: $modId |ModFolderPath: $modFolderPath"
		return $false
	}
	if (-not $gameVersion) {
		$gameVersion = Get-CurrentRimworldVersion
	}

	$identifiersToAdd = @()
	if ($oldmod) {
		$identifiersToAdd += $modObject.Name
		return $identifiersToAdd
	}
	foreach ($identifierItem in $modObject.AboutFileXml.ModMetaData.modDependencies.li) {
		$identifier = $identifierItem.packageId
		if (-not (Test-ValidIdentifier -identifier $identifier)) {
			continue
		}
		if (-not (Get-ModIdentifierAvailable -modIdentifierItem $identifierItem)) {
			WriteMessage -warning "Could not find mod named $($identifierItem.displayName) $($identifierItem.packageId), exiting"
			return $false
		}
		$modPath = Get-ModPathFromDatabase -identifier $identifier
		if (-not $modPath) {
			WriteMessage -warning "Could not find mod for $identifier, exiting"
			return $false
		}
		$subIdentifiers = Get-IdentifiersFromSubMod -modFolderPath $modPath
		if ($subIdentifiers -eq -1) {
			WriteMessage -warning "Could not find mod for $identifier, exiting"
			return $false
		}
		foreach ($subIdentifier in $subIdentifiers) {
			if ($identifiersToAdd -notcontains $subIdentifier.ToLower()) {
				$identifiersToAdd += $subIdentifier.ToLower()
			}
		}
		if ($identifiersToAdd -notcontains $identifier.ToLower()) {
			$identifiersToAdd += $identifier.ToLower()
		}
	}
	if ($modObject.AboutFileXml.ModMetaData.modDependenciesByVersion) {
		foreach ($identifierItem in $modObject.AboutFileXml.ModMetaData.modDependenciesByVersion."v$gameVersion".li) {
			$identifier = $identifierItem.packageId
			if (-not (Test-ValidIdentifier -identifier $identifier)) {
				continue
			}
			if (-not (Get-ModIdentifierAvailable -modIdentifierItem $identifierItem)) {
				WriteMessage -warning "Could not find mod named $($identifierItem.displayName) $($identifierItem.packageId), exiting"
				return $false
			}
			$modPath = Get-ModPathFromDatabase -identifier $identifier
			if (-not $modPath) {
				WriteMessage -warning "Could not find mod for $identifier, exiting"
				return $false
			}
			$subIdentifiers = Get-IdentifiersFromSubMod $modPath
			if ($subIdentifiers -eq -1) {
				WriteMessage -warning "Could not find valid sub-mods for $identifier, exiting"
				return $false
			}
			foreach ($subIdentifier in $subIdentifiers) {
				if ($identifiersToAdd -notcontains $subIdentifier.ToLower()) {
					$identifiersToAdd += $subIdentifier.ToLower()
				}
			}
			if ($identifiersToAdd -notcontains $identifier.ToLower()) {
				$identifiersToAdd += $identifier.ToLower()
			}
		}
	}
	if ($alsoLoadBefore) {
		foreach ($identifier in $modObject.AboutFileXml.ModMetaData.loadAfter.li) {
			if (-not (Test-ValidIdentifier -identifier $identifier)) {
				continue
			}
			if (-not $identifiersToAdd.Contains($identifier.ToLower())) {
				$identifiersToAdd += $identifier.ToLower()
			}
		}
	}
	$identifiersToAdd += $modObject.AboutFileXml.ModMetaData.packageId.ToLower()
	$identifiersToAdd = $identifiersToAdd | Get-Unique
	return $identifiersToAdd
}

function Get-ModIdentifierAvailable {
	param(
		$modIdentifierItem
	)
	if (-not $modIdentifierItem.packageId -and -not $modIdentifierItem.steamWorkshopUrl) {
		WriteMessage -warning "Empty packageId in mod-identifier and no steam id, exiting"
		return $false
	}

	if ($modIdentifierItem.packageId -and (Get-ModPathFromDatabase -identifier $modIdentifierItem.packageId)) {
		return $true
	}

	if ($modIdentifierItem.steamWorkshopUrl) {
		# Get the steam id from the url, fetch all 0-9 characters at the end of the url
		$steamId = $modIdentifierItem.steamWorkshopUrl -replace '.*?(\d+)$', '$1'
		if (-not $steamId -or $steamId -eq "0") {
			WriteMessage -warning "Could not find valid steam id from $($modIdentifierItem.steamWorkshopUrl), exiting"
			return $false
		}
		$modInfo = Get-ModInfo -steamIds $steamId
		if (-not $modInfo.Exists) {
			WriteMessage -warning "Could not find mod with steam id $steamId, exiting"
			return $false
		}
		WriteMessage -progress "Subscribing to mod with steam id $steamId named $($modInfo.Name)"
		Set-ModSubscription -modId $steamId -subscribe $true | Out-Null
		return $true
	}

	WriteMessage -progress "Could not find mod named $($modIdentifierItem.displayName) packageid $($modIdentifierItem.packageId), searching for it on Steam"
	$url = Get-ModLink -modName $modIdentifierItem.displayName -chooseIfNotFound
	if (-not $url) {
		WriteMessage -failure "Could not find mod-link for $($modIdentifierItem.displayName), searching for previous version"
		$url = Get-ModLink -modName $modIdentifierItem.displayName -lastVersion -chooseIfNotFound
	}
	if (-not $url) {
		WriteMessage -failure "Could not find mod-link for $($modIdentifierItem.displayName), exiting"
		return $false
	}
	$modId = $url.Split("=")[-1]
	Set-ModSubscription -modId $modId -subscribe $true | Out-Null
	return $true
}

# Fetches identifiers from a mod-requirement mod
function Get-IdentifiersFromSubMod {
	param (
		$modFolderPath
	)
	if (-not $modFolderPath) {
		$modFolderPath = (Get-Location).Path
	}

	$aboutFile = "$modFolderPath\About\About.xml"
	if (-not (Test-Path $aboutFile)) {
		WriteMessage -warning "Could not find About-file for mod in $modFolderPath"
		return -1
	}
	$aboutFileContent = [xml](Get-Content $aboutFile -Raw -Encoding UTF8)

	$identifiersToReturn = @()
	foreach ($identifierItem in $aboutFileContent.ModMetaData.modDependencies.li) {
		$identifier = $identifierItem.packageId
		if (-not (Test-ValidIdentifier -identifier $identifier)) {
			continue
		}
		if (-not (Get-ModIdentifierAvailable -modIdentifierItem $identifierItem)) {
			WriteMessage -warning "Could not find mod named $($identifierItem.displayName) packageid $($identifierItem.packageId), exiting"
			return -1
		}
		$identifiersToReturn += $identifier.ToLower()
	}
	if ($aboutFileContent.ModMetaData.modDependenciesByVersion) {
		foreach ($identifierItem in $aboutFileContent.ModMetaData.modDependenciesByVersion."v$gameVersion".li) {
			$identifier = $identifierItem.packageId
			if (-not (Test-ValidIdentifier -identifier $identifier)) {
				continue
			}
			if (-not (Get-ModIdentifierAvailable -modIdentifierItem $identifierItem)) {
				WriteMessage -warning "Could not find mod named $($identifierItem.displayName) packageid $($identifierItem.packageId), exiting"
				return -1
			}
			$identifiersToReturn += $identifier.ToLower()
		}
	}
	return $identifiersToReturn
}


# Returns total amount of my published mods
function Get-TotalAmountOfMods {
	param(
		[switch]$NoVs,
		[switch]$NoDependencies
	)
	$allMods = Get-ChildItem -Directory $localModFolder

	WriteMessage -progress "Fetching total amount of mods"
	$progressObject = WriteProgress -initiate -title "Fetching total amount of mods from $folderName" -totalActions $allMods.Count
	foreach ($folder in $allMods) {
		WriteProgress -progressObject $progressObject
		$modObject = Get-Mod -modPath $folder.FullName -noTypes:(-not $NoVs)

		if (-not $modObject.Published) {
			continue
		}
		if (-not $modObject.Mine) {
			continue
		}
		if ($NoVs -and $modObject.HasAssemblies) {
			continue
		}
		if ($NoDependencies -and (Get-IdentifiersFromMod -modObject $modObject).Count -gt 1) {
			continue
		}
		$total++
	}
	WriteProgress -progressObject $progressObject -finished
	return $total
}

# Gets the highest version for a mod dependency
function Get-ModDependencyMaxVersion {
	[CmdletBinding()]
	param(
		$modObject,
		$gameVersion,
		[switch]$supportsLatest,
		[switch]$silent,
		[switch]$returnBlockingDependencies
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			if ($supportsLatest) {
				return $false
			}
			return
		}
	}

	if (-not $modObject.Mine) {
		WriteMessage -failure "$($modObject.Name) is not mine, aborting update"
		if ($supportsLatest) {
			return $false
		}
		return
	}

	if (-not $gameVersion) {
		$gameVersion = Get-CurrentRimworldVersion
	}

	$identifiers = Get-IdentifiersFromMod -modObject $modObject -gameVersion $gameVersion

	if (-not $identifiers) {
		WriteMessage -failure "Could not find identifiers for $($modObject.Name), exiting"
		if ($supportsLatest) {
			return $false
		}
		return
	}

	if ($identifiers.Count -le 1) {
		if ($VerbosePreference) {
			WriteMessage -progress "$($modObject.Name) has no dependecies, exiting"
		}
		if ($supportsLatest) {
			return $true
		}
		return
	}

	if ($returnBlockingDependencies) {
		$returnIdentifiers = @()
	}

	$maxVersion = [version]"0.0"
	foreach ($identifier in $identifiers) {
		if ($identifier -match $modObject.ModId) {
			continue
		}
		$modPath = (Get-ModPathFromDatabase -identifier $identifier)
		if (-not $modPath) {
			WriteMessage -warning "Could not find the mod for identifier $identifier"
			continue
		}
		if (-not (Test-Path $modPath)) {
			WriteMessage -warning "Could not find the folder for $identifier at $modPath"
			continue
		}
		$referenceMod = Get-Mod -modPath $modPath
		$currentMax = $referenceMod.HighestSupportedVersion
		if ($referenceMod.Mine) {
			if ([version]$referenceMod.Version -lt [version]$referenceMod.HighestSupportedVersion) {
				WriteMessage -warning "$identifier has unpublished updates, assumes not ready"
				$currentMax = ($referenceMod.SupportedVersions | Sort-Object)[-2]
			}
		}
		if ($returnBlockingDependencies -and $currentMax -ne (Get-CurrentRimworldVersion)) {
			$returnIdentifiers += $referenceMod
		}
		if (-not $silent -and -not $returnBlockingDependencies) {
			if ($VerbosePreference) {
				WriteMessage -progress "$identifier supports $currentMax"
			}
		}
		if ($maxVersion -eq [version]"0.0") {
			$maxVersion = [version]$currentMax
			continue
		}
		if ($maxVersion -gt [version]$currentMax) {
			$maxVersion = [version]$currentMax
		}
	}
	if ($supportsLatest) {
		return "$maxVersion" -eq (Get-CurrentRimworldVersion)
	}
	if ($returnBlockingDependencies) {
		return $returnIdentifiers
	}
	return "$maxVersion"
}


# Returns a list of all files that have the selected string in their XML
function Get-StringFromModFiles {
	[CmdletBinding()]
	param($searchString,
		$threads = 10,
		[switch]$firstOnly,
		[switch]$noEscape,
		[switch]$alsoCs,
		[switch]$finalOutput,
		[switch]$caseSensitive,
		$fromSave)
	$searchStringConverted = [regex]::escape($searchString)
	if ($noEscape) {
		$searchStringConverted = $searchString
	}
	if ($fromSave) {
		if (-not (Test-Path $fromSave)) {
			WriteMessage -failure "No save-file found from path $fromSave"
			return
		}
		[xml]$saveData = Get-Content $fromSave -Raw -Encoding UTF8
		$identifiers = $saveData.ChildNodes.meta.modIds.li
		$allMods = @()
		foreach ($identifier in $identifiers) {
			$modPath = (Get-ModPathFromDatabase -identifier $identifier)
			if ($modPath) {
				$allMods += Get-Item $modPath
			}
		}
	} else {
		$allMods = Get-ChildItem -Directory $localModFolder
	}
	$allMatchingFiles = @()

	$total = $allMods.Count
	$filterPart = "*.xml"
	if ($alsoCs) {
		$filterPart = ('*.xml', '*.cs')
	}
	foreach ($job in Get-Job) {
		Stop-Job $job | Out-Null
		Remove-Job $job | Out-Null
	}
	$progressObject = WriteProgress -initiate -title "Searching for matches" -totalActions $total

	foreach ($folder in ($allMods | Get-Random -Count $total)) {
		WriteProgress -progressObject $progressObject

		while ((Get-Job -State 'Running').Count -gt $threads) {
			Start-Sleep -Milliseconds 100
		}
		$ScriptBlock = {
			# 0: $folder.FullName 1: $searchStringConverted 2: $filterPart
			$foundFiles = @()
			$searchString = $args[1]
			$baseFolder = Split-Path $args[0]
			Get-ChildItem -Path $args[0] -Recurse -File -Include $args[2] | ForEach-Object { if ((Get-Content -LiteralPath "$($_.FullName)" -Raw -Encoding utf8) -match $searchString) {
					$foundFiles += $_.FullName.Replace("$baseFolder\", "")
				} }
			return $foundFiles
		}
		if ($caseSensitive) {
			$ScriptBlock = {
				# 0: $folder.FullName 1: $searchStringConverted 2: $filterPart
				$foundFiles = @()
				$searchString = $args[1]
				$baseFolder = Split-Path $args[0]
				Get-ChildItem -Path $args[0] -Recurse -File -Include $args[2] | ForEach-Object { if ((Get-Content -LiteralPath "$($_.FullName)" -Raw -Encoding utf8) -cmatch $searchString) {
						$foundFiles += $_.FullName.Replace("$baseFolder\", "")
					} }
				return $foundFiles
			}
		}
		$arguments = @("$($folder.FullName)", $searchStringConverted, $filterPart)
		Start-Job -Name "Find_$($folder.Name)" -ScriptBlock $ScriptBlock -ArgumentList $arguments | Out-Null
		foreach ($job in Get-Job -State Completed) {
			$result = Receive-Job $job
			$allMatchingFiles += $result
			if (-not $finalOutput -and -not $firstOnly) {
				foreach ($file in $result) {
					$fullPath = "$localModFolder\$file".Replace("\", "/")
					Write-Host "file://$fullPath"
				}
			}
			Remove-Job $job | Out-Null
		}
		foreach ($job in Get-Job -State Blocked) {
			WriteMessage -failure "$($job.Name) failed to exit, stopping it."
			Stop-Job $job | Out-Null
			Remove-Job $job | Out-Null
		}
		if ($firstOnly -and $allMatchingFiles.Count -gt 0) {
			break
		}
	}
	SetTerminalProgress -unknown
	$timer.Stop()
	foreach ($job in Get-Job -State Completed) {
		$result = Receive-Job $job
		$allMatchingFiles += $result
		if (-not $finalOutput) {
			foreach ($file in $result) {
				$fullPath = "$localModFolder\$file".Replace("\", "/")
				Write-Host "file://$fullPath"
			}
		}
		Remove-Job $job | Out-Null
	}
	foreach ($job in Get-Job -State Blocked) {
		WriteMessage -failure "$($job.Name) failed to exit, stopping it."
		Stop-Job $job | Out-Null
		Remove-Job $job | Out-Null
	}
	WriteProgress -progressObject $progressObject -finished
	if ($firstOnly -and $allMatchingFiles.Count -gt 0) {
		$fullPath = "$localModFolder\$($allMatchingFiles[0])"
		$number = ((Get-Content $fullPath | select-string $searchStringConverted).LineNumber)[0]
		$applicationPath = $settings.text_editor_path
		$arguments = """$($fullPath)""", "-n$number"
		Start-Process -FilePath $applicationPath -ArgumentList $arguments
		return $allMatchingFiles[0]
	}
	if ($finalOutput) {
		return $allMatchingFiles | Sort-Object
	}
}

# Returns a list of mods that has not been updated to the latest version
# With switch FirstOnly the current directory is changed to the next not-updated mod root path
function Get-NotUpdatedMods {
	[CmdletBinding()]
	param(
		[switch]$FirstOnly,
		[switch]$BetaTested,
		[switch]$NextOnly,
		[switch]$NoVs,
		[switch]$NoDependencies,
		[switch]$IgnoreLastErrors,
		[switch]$NotFinished,
		[switch]$TotalOnly,
		$ModsToIgnore,
		[int]$MaxToFetch = -1,
		[switch]$RandomOrder,
		[switch]$ListMissingDependencies,
		$MaxCodeSize = [ModCodeSize]::Huge
	)
	$currentVersionString = Get-CurrentRimworldVersion
	$allMods = Get-ChildItem -Directory $localModFolder
	if ($RandomOrder) {
		$allMods = $allMods | Sort-Object { Get-Random }
	}

	$betaProgressFile = "E:\ModPublishing\BetaProgress.json"
	$betaProgress = Get-Content -Path $betaProgressFile -Raw -Encoding UTF8 | ConvertFrom-Json
	if ($betaProgress -and -not $TotalOnly) {
		if ($BetaTested) {
			$allMods = $allMods | Where-Object { $betaProgress.$($_.Name) -eq "Success" }
		} else {
			$allMods = $allMods | Where-Object { $betaProgress.$($_.Name) -ne "Success" }
		}
		WriteMessage -progress "Searching beta successful = $BetaTested, $($allMods.Count) mods, max codesize $MaxCodeSize"
	}
	if ($MaxToFetch -eq 0) {
		$MaxToFetch = $allMods.Length
	}
	if (-not $ModsToIgnore) {
		$ModsToIgnore = @()
	}
	if ($ListMissingDependencies) {
		$DependenciesList = @{}
	}
	$currentFolder = (Get-Location).Path
	if ($currentFolder -eq $localModFolder -and $NextOnly) {
		$NextOnly = $false
		$FirstOnly = $true
		WriteMessage -warning "Standing in root-dir, will assume FirstOnly instead of NextOnly"
	}
	$foundStart = $false
	$counter = 0
	SetTerminalProgress -unknown
	foreach ($folder in $allMods) {
		if ($NextOnly -and (-not $foundStart)) {
			if ($folder.FullName -eq $currentFolder) {
				if ($VerbosePreference) {
					WriteMessage -progress "Will search for next mod from $currentFolder"
				}
				$foundStart = $true
			}
			continue
		}
		if ($MaxToFetch -gt 0 -and $counter -ge $MaxToFetch) {
			return $false
		}
		if ($ModsToIgnore.Contains($folder.Name)) {
			continue
		}
		$modObject = Get-Mod -modName $folder.Name -fast:$TotalOnly

		if (-not $modObject.Published) {
			if ($VerbosePreference) {
				WriteMessage -progress "Skipping $($modObject.Name) since its not published"
			}
			continue
		}
		if (-not $modObject.Mine) {
			if ($VerbosePreference) {
				WriteMessage -progress "Skipping $($modObject.Name) since its not mine"
			}
			continue
		}

		if ([int](Get-ModCodeSize -modObject $modObject) -gt [int]$MaxCodeSize) {
			if ($VerbosePreference) {
				WriteMessage -progress "Skipping $($modObject.Name) since its code size is too large ($($modObject.MetadataFileJson.CodeSize))"
			}
			continue
		}
		if (-not $IgnoreLastErrors -and (Test-Path "$($folder.FullName)Source\lastrun.log")) {
			if ($VerbosePreference) {
				WriteMessage -progress "Skipping $($modObject.Name) since it has previous errors logged"
			}
			continue
		}
		if ($NoVs -and -not $TotalOnly) {
			$cscprojFiles = Get-ChildItem -Recurse -Path $folder.FullName -Include *.csproj
			if ($cscprojFiles.Length -gt 0) {
				if ($VerbosePreference) {
					WriteMessage -progress "Skipping $($modObject.Name) since it has vs-files"
				}
				continue
			}
		}

		if ($NoDependencies -and -not $TotalOnly -and (Get-IdentifiersFromMod -modObject $modObject -bare -gameVersion Get-LastRimworldVersion).Count -gt 1) {
			if ($VerbosePreference) {
				WriteMessage -progress "Skipping $($modObject.Name) since it has dependencies"
			}
			continue
		}

		if ($modObject.SupportedVersions.Contains($currentVersionString)) {
			if ([version]$modObject.Version -ge [version]$modObject.HighestSupportedVersion) {
				if ($VerbosePreference) {
					WriteMessage -progress "Skipping $($modObject.Name) since its already published"
				}
				continue
			}
			if (-not $NotFinished) {
				if ($VerbosePreference) {
					WriteMessage -progress "Skipping $($modObject.Name) since it already supports $currentVersionString"
				}
				continue
			}
		}

		if ($NotFinished -and -not $TotalOnly) {
			if ((Get-Item $modObject.ChangelogPath).LastWriteTime -ge (Get-Item $modObject.AboutFilePath).LastWriteTime.AddMinutes(-5)) {
				if ($VerbosePreference) {
					WriteMessage -progress "Skipping $($modObject.Name) since its already published"
				}
				continue
			}
			if (-not $modObject.SupportedVersions.Contains($currentVersionString)) {
				if ($VerbosePreference) {
					WriteMessage -progress "Skipping $($modObject.Name) since it does not support $currentVersionString"
				}
				continue
			}
		}

		if ($TotalOnly) {
			$counter++
			SetTerminalProgress -progressPercent ($counter / $MaxToFetch * 100)
			continue
		}

		if ($FirstOnly -or $NextOnly) {
			Set-Location $folder.FullName
			return $true
		}

		if ($ListMissingDependencies) {
			$blockingDependencies = Get-ModDependencyMaxVersion -modObject $modObject -returnBlockingDependencies
			foreach ($mod in $blockingDependencies) {
				if (-not $DependenciesList.ContainsKey($mod.ModId)) {
					$DependenciesList["$($mod.Modid)"] = "$($mod.DisplayName) - $($mod.ModUrl)"
				}
			}
		} else {
			Write-Host $modObject.Name
		}

		$counter++
	}
	SetTerminalProgress
	if ($TotalOnly) {
		return $counter
	}
	if ($DependenciesList) {
		return $DependenciesList
	}
}

# Looks for all files that is not supposed to be there
function Get-NonValidFilesFromMod {
	param($modObject)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	$nonGraphicFiles = Get-ChildItem -Exclude *.png, *.jpg -File -Recurse -Path "$($modObject.ModFolderPath)\Textures"
	$nonXmlFiles = Get-ChildItem -Exclude Textures, Source, Assemblies, Sounds, News, .github -Directory -Path $modObject.ModFolderPath | Get-ChildItem -Exclude *.xml, Preview.png,Changelog.txt,PublishedFileId.txt,ModIcon.png  -File | Where-Object { $_.FullName -notmatch "Assemblies" }

	if ($nonGraphicFiles) {
		WriteMessage -warning "Found $($nonGraphicFiles.Count) non-graphic files in Texture-folder"
		Write-Host ($nonGraphicFiles -join "`n")
	}
	if ($nonXmlFiles) {
		WriteMessage -warning "Found $($nonXmlFiles.Count) non-xml files in the data-folders"
		Write-Host ($nonXmlFiles -join "`n")
	}
}

# Returns the oldest mod in the mod-directory, optional VS-only switch
function Get-OldestMod {
	param([switch]$OnlyVS)
	$allMods = Get-ChildItem -Path "$localModFolder\*\About\About.xml" | Sort-Object -Property LastWriteTime
	foreach ($aboutFile in $allMods) {
		Set-Location $aboutFile.Directory.Parent
		if (-not (Get-OwnerIsMeStatus)) {
			continue
		}
		if ($OnlyVS) {
			$cscprojFiles = Get-ChildItem -Recurse -Path $aboutFile.Directory.Parent -Include *.csproj
			if ($cscprojFiles.Count -eq 0) {
				continue
			}
		}
		WriteMessage -success "$($aboutFile.Directory.Parent.Name) was updated $($aboutFile.LastWriteTimeString)"
		break
	}
}

# Gets the current rimworld version
function Get-CurrentRimworldVersion {
	param(
		[switch]$versionObject,
		[switch]$force
	)
	$rimworldVersionFile = "$localModFolder\..\Version.txt"
	$currentRimworldVersion = [version]([regex]::Match((Get-Content $rimworldVersionFile -Raw -Encoding UTF8), "[0-9]+\.[0-9]+")).Value
	if (-not $force -and $inBeta) {
		$currentRimworldVersion = [version]"$($currentRimworldVersion.Major).$($currentRimworldVersion.Minor - 1)"
	}
	if ($versionObject) {
		return $currentRimworldVersion
	}
	return "$($currentRimworldVersion.Major).$($currentRimworldVersion.Minor)"
}

# Gets the last rimworld version
function Get-LastRimworldVersion {
	$currentVersion = Get-CurrentRimworldVersion -versionObject
	return "$($currentVersion.Major).$($currentVersion.Minor - 1)"
}

function Get-SteamRateLimit {
	[CmdletBinding()]
	param (	)

	if (-not $globalRequestLog) {
		$globalRequestLog = @()
	}

	# Calculate the number of requests in the last 5 minutes
	$timeWindow = [datetime]::UtcNow.AddMinutes(-5)
	$recentRequests = $globalRequestLog | Where-Object { $_ -gt $timeWindow }

	if ($recentRequests.Count -ge 200) {
		WriteMessage -progress "Steam API rate limit reached, waiting for requests to clear"
		while ($recentRequests.Count -ge 200) {
			Start-Sleep -Seconds 1  # Wait and re-check every second
			$recentRequests = $globalRequestLog | Where-Object { $_ -gt $timeWindow }
		}
	}
	$globalRequestLog += [datetime]::UtcNow

	return
}

function Invoke-SteamApi {
	[CmdletBinding()]
	param(
		$uri,
		$method = "Get",
		$body
	)

	Get-SteamRateLimit
	for ($i = 0; $i -lt 5; $i++) {
		Write-Debug "Calling url: $uri with body: $body, method: $method"
		try {
			if ($body) {
				$response = Invoke-RestMethod -Uri $uri -Method $method -Body $body -ContentType "application/x-www-form-urlencoded"
			} else {
				$response = Invoke-RestMethod -Uri $uri -Method $method
			}
		} catch {
			if ($_.Exception.Message -match "429") {
				WriteMessage -progress "Steam API rate limit reached, waiting for 5 seconds"
				Start-Sleep -Seconds 5
				continue
			} else {
				WriteMessage -failure "Failed to call Steam API: $($_.Exception.Message)"
				return
			}
		}
		Write-Verbose "Response: $($response | ConvertTo-Json -Depth 5)"
		return $response
	}
}

function Get-LatestPackageVersion {
	[CmdletBinding()]
	param (
		[string]$packageId,
		[switch]$clearCache
	)

	$packageId = $packageId.ToLowerInvariant()
	$cacheFile = "$env:TEMP\nuget_version_cache.json"
	$cacheTTL = [TimeSpan]::FromHours(1)

	# Load or initialize cache
	if (Test-Path $cacheFile) {
		$cache = Get-Content $cacheFile | ConvertFrom-Json -ErrorAction Ignore
	} else {
		$cache = @{}
	}

	$now = Get-Date
	if ($cache.$packageId -and ($now - [datetime]$cache.$packageId.Timestamp) -lt $cacheTTL) {
		if ($clearCache) {
			Write-Verbose "Clearing cache for package $packageId"
			$cache.$packageId = $null
		} else {
			Write-Verbose "Using cached version for package $packageId"
			return $cache.$packageId.Version
		}
	}

	# Query NuGet
	$index = Invoke-RestMethod "https://api.nuget.org/v3/index.json"
	$pkgBase = ($index.resources | Where-Object { $_.'@type' -eq 'PackageBaseAddress/3.0.0' }).'@id'
	Write-Verbose "Fetching: $pkgBase$packageId/index.json"
	$versions = (Invoke-RestMethod "$pkgBase$packageId/index.json").versions

	$latest = $versions | Sort-Object { [Version]($_ -replace '[^0-9\.].*','') } -Descending | Select-Object -First 1

	$useWildcard = $latest -notlike "*-*"
	$result = if ($useWildcard) {
		"*"
	} else {
		$latest
	}

	$cache.$packageId = @{ Version = $result; Timestamp = $now }
	$cache | ConvertTo-Json -Depth 5 | Set-Content $cacheFile

	return $result
}

function Get-SteamWorkshopModInfo {
	param (
		[string]$modId
	)
	$result = [ordered]@{
		SteamId       = "$modId"
		Exists        = $false
		Name          = $null
		AuthorName    = $null
		Subscriptions = $null
		Tags          = @()
		Visibility    = $null
		PreviewUrl    = $null
		Description   = $null
	}
	$url = "https://steamcommunity.com/sharedfiles/filedetails/?id=$modId"
	Import-Module -ErrorAction Stop PowerHTML -Verbose:$false
	$fileName = $url.Split("=")[1].Trim()
	$filePath = "$($env:TEMP)\$fileName.html"
	$metaPath = "$env:TEMP\$fileName.headers.json"
	$prevMeta = $null
	if (Test-Path $metaPath) {
		try {
			$prevMeta = Get-Content -Raw $metaPath | ConvertFrom-Json
		} catch {
			$prevMeta = $null
		}
	}
	# Build conditional headers
	$reqHeaders = @{ 'User-Agent' = 'Mozilla/5.0' }  # helps avoid some blocks
	$cacheTTL = [TimeSpan]::FromHours(12)
	if ($prevMeta) {
		if ($prevMeta.ETag) {
			$reqHeaders['If-None-Match'] = $prevMeta.ETag
		} elseif ($prevMeta.'Last-Modified') {
			# RFC1123 format
			$reqHeaders['If-Modified-Since'] = ([datetime]$prevMeta.'Last-Modified').ToUniversalTime().ToString('r')
		} elseif ($prevMeta.Downloaded) {
			# Fallback: use our last download time
			$reqHeaders['If-Modified-Since'] = ([datetime]$prevMeta.Downloaded).ToUniversalTime().ToString('r')
		}
	}

	if ((Test-Path $filePath) -and (-not (Get-Content -Path $filePath -Raw).StartsWith("<!DOCTYPE html>") -or ((Get-Content -Path $filePath) -match "Please try again later"))) {
		Remove-Item $filePath -Force
	}
	$useCache = $false
	if ($prevMeta -and (Test-Path $filePath)) {
		$age = (Get-Date) - [datetime]$prevMeta.Downloaded
		$useCache = ($age -lt $cacheTTL) -and ((Get-Content -Path $filePath -Raw).StartsWith("<!DOCTYPE html>")) -and (-not ((Get-Content -Path $filePath) -match "Please try again later"))
	}
	$pendingSuccessUpdate = $false
	$responseHeaders = $null
	$downloadedAt = $null
	if (-not $useCache) {
		WriteMessage -progress "Fetching data from $url"
		$downloaded = $false
		for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
			Invoke-SteamThrottleWait -Reason "Steam fetch attempt $attempt for $modId"
			Set-SteamThrottleAttempt
			try {
				$resp = Invoke-WebRequest -Uri $url -Headers $reqHeaders -ErrorAction Stop
				Set-Content -Path $filePath -Value $resp.Content -Encoding UTF8
				$responseHeaders = $resp.Headers
				$downloadedAt = Get-Date
				$pendingSuccessUpdate = $true
				$downloaded = $true
				break
			} catch {
				$webResp = $_.Exception.Response
				if ($webResp -and ($webResp.StatusCode.value__ -eq 304)) {
					Update-SteamThrottleState -Success
					$downloaded = $true
					$timestamp = Get-Date
					if ($prevMeta) {
						$prevMeta.Downloaded = $timestamp
						$prevMeta | ConvertTo-Json | Set-Content -Path $metaPath -Encoding UTF8
					} else {
						@{
							Downloaded = $timestamp
						} | ConvertTo-Json | Set-Content -Path $metaPath -Encoding UTF8
					}
					WriteMessage -progress "Cache valid (304 Not Modified), using $filePath"
					break
				}
				Update-SteamThrottleState -Failure
				WriteMessage -warning "Attempt $attempt : Failed to fetch data from $url"
			}
		}
		if ($pendingSuccessUpdate -and $downloaded) {
			@{
				ETag            = $responseHeaders.ETag
				'Last-Modified' = $responseHeaders['Last-Modified']
				Downloaded      = $downloadedAt
			} | ConvertTo-Json | Set-Content -Path $metaPath -Encoding UTF8
		}
	} else {
		WriteMessage -progress "Using cached page for $modId"
	}
	if (-not (Test-Path $filePath)) {
		WriteMessage -warning "Could not fetch data from $url"
		return $result
	}
	if ((Test-Path $filePath) -and (Get-Content -Path $filePath) -match "Please wait and try your request again later") {
		Update-SteamThrottleState -Failure
		$pendingSuccessUpdate = $false
		WriteMessage -progress "Steam rate limit hit, subscribing instead of fetching data"
		Set-ModSubscription -modId $modId -subscribe $true -noCheck
		$modData = Get-Mod -modPath "E:\SteamLibrary\steamapps\workshop\content\294100\$modId"
		if ($modData.PublishedId) {
			$result.Name = $modData.DisplayName
			$result.AuthorName = $modData.Author
			$result.Visibility = "Unlisted"
			$result.Exists = $true
			$result.Tags = $modData.SupportedVersions
			$result.Description = $modData.Description
		} else {
			WriteMessage -warning "Could not fetch data for $url due to the item not existing"
		}
		return $result
	}
	if ((Get-Content -Path $filePath) -match "Please try again later" -or -not (Get-Content -Path $filePath).StartsWith("<!DOCTYPE html>")) {
		Update-SteamThrottleState -Failure
		$pendingSuccessUpdate = $false
		WriteMessage -progress "Failed to fetch data from $url, may be removed. Trying a few more times."
		$fallbackSuccess = $false
		for ($i = 0; $i -lt 3; $i++) {
			Invoke-SteamThrottleWait -Reason "Steam fallback attempt $($i + 1) for $modId"
			Set-SteamThrottleAttempt
			$fallbackHtml = ConvertFrom-Html -URI $url -ErrorAction SilentlyContinue
			if ($fallbackHtml) {
				$fallbackContent = $fallbackHtml.InnerHtml
				if ($fallbackContent) {
					Set-Content -Path $filePath -Value $fallbackContent -Encoding UTF8
					if ($fallbackContent -notmatch "Please try again later") {
						Update-SteamThrottleState -Success
						$fallbackSuccess = $true
						$timestamp = Get-Date
						@{
							ETag            = $null
							'Last-Modified' = $null
							Downloaded      = $timestamp
						} | ConvertTo-Json | Set-Content -Path $metaPath -Encoding UTF8
						break
					}
				}
			}
			Update-SteamThrottleState -Failure
		}
		if (-not $fallbackSuccess -or (Get-Content -Path $filePath) -match "Please try again later" -or -not (Get-Content -Path $filePath).StartsWith("<!DOCTYPE html>")) {
			WriteMessage -warning "Could not fetch data from $url after multiple attempts"
			return $result
		}
	}
	if ($pendingSuccessUpdate) {
		Update-SteamThrottleState -Success
		$pendingSuccessUpdate = $false
	}
	$html = ConvertFrom-Html -Path $filePath -ErrorAction SilentlyContinue

	try {
		if ($html.InnerText -match "You must be logged in to view this item.") {
			WriteMessage -warning "$url requires login, can not fetch data"
			return $result
		}

		if ($html.InnerText -match "An error was encountered while processing your request:") {
			return $result
		}
		$result.Exists = $true
		if ($html.InnerText -match "Current visibility: Unlisted") {
			$result.Visibility = "Unlisted"
		}
		if ($html.InnerText -match "Current visibility: Hidden") {
			$result.Visibility = "Hidden"
		}
		if ($html.InnerText -match "Current visibility: Friends-only") {
			$result.Visibility = "Friends"
		}
		$result.Visibility = "Public"

		$result.Name = $html.SelectNodes("//div[@class='workshopItemTitle']").InnerText

		$result.Subscriptions = $html.SelectNodes("//table").SelectNodes("//td")[2].InnerText.Replace(",", "")

		$result.AuthorName = $html.SelectNodes("//div[@class='breadcrumbs']").Nodes().InnerText[-2].Replace("'s Workshop", "")

		$imgSrc = $html.SelectNodes("//img[contains(@id, 'previewImageMain')]")
		if (-not $imgSrc) {
			$imgSrc = $html.SelectNodes("//img[contains(@id, 'previewImage')]")
		}
		if ($imgSrc) {
			$result.PreviewUrl = "$($imgSrc.GetAttributeValue('src', '').Split('?')[0])"
		}
		$result.Description = $html.SelectNodes("//div[@class='workshopItemDescription']").InnerText.Trim()

		$versionsHtml = $html.SelectNodes("//div[contains(@class, 'rightDetailsBlock')]")[0].InnerText.Trim()
		$result.Tags = $versionsHtml.Replace("Tags:", ",").Replace(" ", "").Split(",") | Where-Object { $_ -and $_ -match "^[0-9]+\.[0-9]+$" }
	} catch {
		WriteMessage -warning  "Failed to fetch data from $url `n$($_.ScriptStackTrace)`n$_"
	}
	return $result
}


function Get-ModInfo {
	[CmdletBinding()]
	param (
		[string[]]$steamIds,
		[switch]$expandAuthor,
		[switch]$forceRefresh,
		[switch]$apiOnly
	)

	$cacheDuration = [TimeSpan]::FromMinutes(10)
	$now = Get-Date

	$idsToFetch = @()
	$returnArray = @()

	if (-not $forceRefresh) {
		foreach ($id in $steamIds) {
			if ($Global:ModInfoCache.ContainsKey($id)) {
				$cacheEntry = $Global:ModInfoCache[$id]
				if ($now - $cacheEntry.Timestamp -lt $cacheDuration) {
					$returnArray += $cacheEntry.ModInfo
					WriteMessage -progress "Cache hit for mod ID $id"
					continue
				}
			}
			$idsToFetch += $id
		}
	} else {
		Write-Verbose "Force refresh enabled, fetching all mod details"
		$idsToFetch = $steamIds
	}

	if ($idsToFetch.Count -gt 0) {
		# Calculate the number of items to fetch
		$itemCount = $idsToFetch.Count

		# API endpoint for fetching published file details
		$uri = "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/"

		# Build the POST parameters as a hashtable. Note that itemcount is sent as a string.
		$postParams = @{
			"itemcount" = "$itemCount"
		}
		# Add each mod ID in the proper key format expected by the API.
		for ($i = 0; $i -lt $itemCount; $i++) {
			$postParams["publishedfileids[$i]"] = $idsToFetch[$i]
		}

		# Convert the hashtable to URL-encoded form data
		$encodedEntries = $postParams.GetEnumerator() | ForEach-Object {
			[System.Net.WebUtility]::UrlEncode($_.Key) + "=" + [System.Net.WebUtility]::UrlEncode($_.Value)
		}
		$encodedBody = $encodedEntries -join "&"

		# Make the POST request and parse the JSON response
		Write-Verbose "Fetching mod details for IDs: $($idsToFetch -join ', ')"
		Write-Debug "Calling url: $uri with body: $encodedBody, itemcount: $itemCount, expandAuthor: $expandAuthor"
		$response = Invoke-SteamApi -uri $uri -method Post -body $encodedBody

		# Loop over each mod's details in the response
		foreach ($details in $response.response.publishedfiledetails) {
			if ($null -eq $details) {
				WriteMessage -warning "No details found for mod ID $($details.publishedfileid)"
				$modInfo = @{
					SteamId       = "$($details.publishedfileid)"
					Exists        = $false
					Name          = "Unknown"
					Author        = "Unknown"
					PreviewUrl    = ""
					Subscriptions = 0
					Visibility    = "Unknown"
					Tags          = ""
					Description   = ""
				}
			} elseif ($details.result -eq 9) {
				if ($apiOnly) {
					WriteMessage -warning "Mod ID $($details.publishedfileid) is not found via API, skipping manual fetch"
					$modInfo = @{
						SteamId       = "$($details.publishedfileid)"
						Exists        = $true
						Name          = "Unknown"
						Author        = "Unknown"
						PreviewUrl    = ""
						Subscriptions = 0
						Visibility    = "Unlisted"
						Tags          = ""
						Description   = ""
					}
					$returnArray += $modInfo
					continue
				}

				WriteMessage -warning "Mod ID $($details.publishedfileid) is not found via API, scraping manually"
				$modInfo = Get-SteamWorkshopModInfo -modId $details.publishedfileid
			} elseif ($details.result -eq 1) {
				Write-Debug "Found details for mod ID $($details.publishedfileid): $($details | ConvertTo-Json -Depth 5)"
				$modName = $details.title
				$author = $details.creator
				if ($expandAuthor) {
					$author = Get-AuthorInformation -authorId $details.creator
				}
				$previewUrl = $details.preview_url
				$subscriptions = $details.subscriptions
				$visibility = $details.visibility
				$tags = $details.tags | ForEach-Object { $_.tag } | Where-Object { $_ -match "^[0-9]+\.[0-9]+$" } | Sort-Object
				$visibility = switch ($visibility) {
					0 {
						"Public"
					}
					1 {
						"Friends"
					}
					2 {
						"Private"
					}
					3 {
						"Unlisted"
					}
					default {
						"Unknown"
					}
				}

				$modInfo = @{
					SteamId       = "$($details.publishedfileid)"
					Exists        = $true
					Name          = $modName
					Author        = $author
					PreviewUrl    = $previewUrl
					Subscriptions = $subscriptions
					Visibility    = $visibility
					Tags          = $tags
					Description   = $details.description
				}
			} else {
				$modInfo = @{
					SteamId       = "$($details.publishedfileid)"
					Exists        = $false
					Name          = "Unknown"
					Author        = "Unknown"
					PreviewUrl    = ""
					Subscriptions = 0
					Visibility    = "Unknown"
					Tags          = ""
					Description   = ""
				}
				WriteMessage -warning "Failed to fetch details for mod ID $($details.publishedfileid)"
				Write-Verbose "Response details: $($details | ConvertTo-Json -Depth 5)"
				Write-Debug "Response body: $($response | ConvertTo-Json -Depth 5)"

			}
			$Global:ModInfoCache[$modInfo.SteamId] = @{
				Timestamp = $now
				ModInfo   = $modInfo
			}
			$returnArray += $modInfo
		}
	}
	return $returnArray
}

function Get-AuthorInformation {
	[CmdletBinding()]
	param (
		$authorId
	)

	# Build the request URL using the creator's Steam ID
	$userSummariesUri = "https://api.steampowered.com/ISteamUser/GetPlayerSummaries/v2/?key=$steamApiKey&steamids=$authorId"

	# Fetch the user summaries from Steam
	$userResponse = Invoke-SteamApi -uri $userSummariesUri -Method Get

	# The response structure contains an array of players
	if ($userResponse.response.players -and $userResponse.response.players.Count -gt 0) {
		$player = $userResponse.response.players[0]
		$steamPersonaName = $player.personaname
		return $steamPersonaName
	}

	return "Unknown Author"
}

function Get-ModPreviewImages {
	[CmdletBinding()]
	param (
		$url,
		$previewSavePath
	)
	# WriteMessage -progress "Fetching $url"
	Import-Module -ErrorAction Stop PowerHTML -Verbose:$false
	$fileName = $url.Split("=")[1].Trim()
	$filePath = "$($env:TEMP)\$fileName.html"
	if (Test-Path $filePath) {
		$counter = 0
		while ((Get-Content -Path $filePath) -match "Please try again later") {
			(ConvertFrom-Html -URI $url).InnerHtml | Out-File $filePath
			$counter++
			if ($counter -gt 5) {
				break
			}
		}
	}
	if (-not (Test-Path $filePath) -or (Get-Item $filePath).LastWriteTime -lt ((get-date).AddMinutes(-$cacheTime))) {
		(ConvertFrom-Html -URI $url).InnerHtml | Out-File $filePath
	}
	$html = ConvertFrom-Html -Path $filePath
	try {
		if ($html.InnerText -match "You must be logged in to view this item.") {
			WriteMessage -warning "$url requires login, can not fetch data"
			return $false
		}

		if ($html.InnerText -match "An error was encountered while processing your request:") {
			WriteMessage -warning "An error was encountered while processing your request: $url"
			return $false
		}
		if (-not (Test-Path $previewSavePath)) {
			WriteMessage -warning "$previewSavePath does not exist, will not download preview images"
			return $false
		}
		$previewNodes = $html.SelectNodes("//div[@class='highlight_strip_item highlight_strip_screenshot']")
		if (-not $previewNodes) {
			WriteMessage -progress  "No preview images found, ignoring"
			return $true
		}
		$counter = 0
		WriteMessage -progress  "Trying to download $($previewNodes.Count) preview images"
		$total = $previewNodes.Count

		$progressObject = WriteProgress -initiate -title "Downloading previews" -totalActions $total
		for ($i = 1; $i -le $previewNodes.Count; $i++) {
			WriteProgress -progressObject $progressObject
			$node = $previewNodes[$i - 1]
			$image = $node.ChildNodes | Where-Object -Property Name -eq img
			if (-not $image) {
				continue
			}
			$imageSource = $image.GetAttributeValue("src", "").Split("?")[0]
			$ProgressPreference = 'SilentlyContinue'
			$request = Invoke-WebRequest -Uri $imageSource -MaximumRedirection 0 -ErrorAction Ignore
			$extension = $request.Headers['Content-Type'].Split('/')[1].Replace("jpeg", "jpg")
			$outputPath = "$previewSavePath\$i.$extension"
			Invoke-WebRequest $imageSource -OutFile $outputPath
			$ProgressPreference = 'Continue'
			if ((Get-Item $outputPath).Length -gt 1MB) {
				WriteMessage -progress "Lowering the size of previewimage to below 1MB"
				Set-ImageSizeBelow -imagePath $outputPath -sizeInKb 999
			}
			$counter++
		}
		WriteProgress -progressObject $progressObject -finished
		WriteMessage -success "Saved $counter preview-images to $previewSavePath"
	} catch {
		WriteMessage -warning  "Failed to fetch data from $url `n$($_.ScriptStackTrace)`n$_"
		return $false
	}
	if ($counter -eq 0) {
		WriteMessage "No preview images found in $url"
	}
	return $true
}


function Get-NextVersionNumber {
	param (
		[version]$currentVersion,
		[version]$referenceVersion
	)
	if (-not $referenceVersion) {
		$referenceVersion = Get-CurrentRimworldVersion -versionObject
	}

	if ($currentVersion.Major -ne $referenceVersion.Major) {
		return [version]"$($referenceVersion.Major).$($referenceVersion.Minor).0"
	}
	if ($currentVersion.Minor -ne $referenceVersion.Minor) {
		return [version]"$($referenceVersion.Major).$($referenceVersion.Minor).0"
	}
	return [version]"$($currentVersion.Major).$($currentVersion.Minor).$($currentVersion.Build + 1)"
}

function Get-ModLink {
	param (
		$modName,
		[switch]$chooseIfNotFound,
		[switch]$lastVersion,
		[switch]$openFolder
	)

	Import-Module -ErrorAction Stop PowerHTML -Verbose:$false
	$modNameUrlEncoded = [System.Web.HTTPUtility]::UrlEncode($modName)
	$modVersion = Get-CurrentRimworldVersion
	if ($lastVersion) {
		$modVersion = "$((Get-CurrentRimworldVersion -versionObject).Major).$((Get-CurrentRimworldVersion -versionObject).Minor - 1)"
	}
	$searchString = "https://steamcommunity.com/workshop/browse/?appid=294100&browsesort=textsearch&section=items&requiredtags%5B%5D=Mod&requiredtags%5B%5D=$modVersion&searchtext=$modNameUrlEncoded"
	$html = ConvertFrom-Html -URI $searchString

	$counter = 0
	foreach ($title in $html.SelectNodes("//div[contains(@class, 'workshopItemTitle')]").InnerText) {
		$titleDecoded = [System.Web.HTTPUtility]::HtmlDecode($title)
		if ($titleDecoded -eq $modName) {
			WriteMessage -success "Found mod named $modName"
			$item = $html.SelectNodes("//div[contains(@class, 'workshopItem')]")
			$linkNode = $item.ChildNodes | Where-Object -Property Name -eq a | Where-Object -Property InnerText -eq $title
			$link = $linkNode.GetAttributeValue("href", "").Split("&")[0]
			if ($openFolder) {
				$modId = $link.Split("=")[1]
				$modFolder = "$localModFolder\..\..\..\workshop\content\294100\$modId"
				if (-not (Test-Path $modFolder)) {
					WriteMessage -failure "Mod not downloaded, cannot open modfolder: $link"
					return $link
				}
				explorer.exe $modFolder
				return
			}
			return $link
		}
		$counter++
	}

	WriteMessage -warning "No mod named $modName found"
	if (-not $chooseIfNotFound) {
		return
	}

	$counter = 1
	foreach ($title in $html.SelectNodes("//div[contains(@class, 'workshopItemTitle')]").InnerText) {
		$titleDecoded = [System.Web.HTTPUtility]::HtmlDecode($title)
		$authorName = $html.SelectNodes("//a[contains(@class, 'workshop_author_link')]")[$counter - 1].InnerText
		Write-Host "$counter - $titleDecoded ($authorName)"
		$counter++
		if ($counter -gt 24) {
			break
		}
	}
	$answer = [int](ReadHost "Select matching, or empty for exit")
	if ($answer) {
		$answer--
		$title = $html.SelectNodes("//div[contains(@class, 'workshopItemTitle')]")[$answer].InnerText
		$titleDecoded = [System.Web.HTTPUtility]::HtmlDecode($title)
		$items = $html.SelectNodes("//div[contains(@class, 'workshopItem')]")
		$linkNode = $items.ChildNodes | Where-Object -Property Name -eq a | Where-Object -Property InnerText -eq $title
		if (-not $linkNode) {
			WriteMessage -failure "Could not find the link for $title"
			return
		}
		$link = $linkNode.GetAttributeValue("href", "").Split("&")[0]
		WriteMessage -success "Found link for mod named $modName"
		if ($openFolder) {
			$modId = $link.Split("=")[1]
			$modFolder = "$localModFolder\..\..\..\workshop\content\294100\$modId"
			if (-not (Test-Path $modFolder)) {
				WriteMessage -failure "Mod not downloaded, cannot open modfolder: $link"
				return $link
			}
			explorer.exe $modFolder
			return
		}
		return $link
	} else {
		WriteMessage -message "No selection made, exiting"
	}
}


# Scans all mods for Manifests containing logic for load-order. Since vanilla added this its no longer needed.
function Get-WrongManifest {
	$allMods = Get-ChildItem -Directory $localModFolder
	foreach ($folder in $allMods) {
		if (-not (Test-Path "$($folder.FullName)\About\Manifest.xml")) {
			continue
		}
		$manifestFile = "$($folder.FullName)\About\Manifest.xml"
		if ((Get-Content -path $manifestFile -Raw -Encoding UTF8).Contains("<li>")) {
			explorer.exe $manifestFile
			Set-Location $folder.FullName
			return
		}
	}
}

#endregion

#region Rimworld-game functions

# Starts rimworld with mods active from a save-game
function Start-RimworldSave {
	param()

	$saveFolder = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Saves"
	$modFile = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\ModsConfig.xml"
	$allSaves = Get-ChildItem $saveFolder | Sort-Object -Property LastWriteTime -Descending

	$counter = 0
	foreach ($save in $allSaves) {
		$counter++
		Write-Host "$($counter): $($save.BaseName) ($($save.LastWriteTime))"
		if ($counter % 5 -eq 0) {
			$answer = ReadHost "Select save to start or empty to list five more"
			if ($answer -and (([int]$counter - 5)..[int]$counter) -contains $answer) {
				$selectedSave = $allSaves[$answer - 1]
				WriteMessage -progress "Selected $($selectedSave.BaseName), parsing"
				$modFileXml = [xml](Get-Content $modFile -Encoding UTF8)
				$saveFileXml = [xml](Get-Content $selectedSave.FullName -Encoding UTF8)
				$counter = -1
				foreach ($modId in $saveFileXml.savegame.meta.modIds.li) {
					$counter++
					if ($modId.StartsWith("ludeon.")) {
						continue
					}
					WriteMessage -progress "Checking status for mod with id $modId"
					if (Get-ModPathFromDatabase -identifier $modId) {
						WriteMessage -success "Found mod with id $modId in cache"
						continue
					}
					$modName = $saveFileXml.savegame.meta.modNames.li[$counter]
					WriteMessage -warning "$modName with id $modId not found, finding"
					$result = Set-ModSubscription -modName $modName -subscribe $true
					if (-not $result) {
						WriteMessage -failure "Failed to find $modName with id $modId"
					}
				}
				$modFileXml.ModsConfigData.activeMods.set_InnerXML($saveFileXml.savegame.meta.modIds.InnerXml)
				$modFileXml.Save($modFile)
				$applicationPath = $settings.steam_path
				$arguments = "-applaunch 294100"
				Stop-RimWorld
				Set-RimworldRunMode
				Start-Process -FilePath $applicationPath -ArgumentList $arguments
				return
			}
		}
	}
}

function Start-RimworldBlob {
	param(
		$blob
	)

	WriteMessage -progress "Starting rimworld with mods from blob"
	Get-ModsInBlob -blob $blob -waitForDownload

	# Uses regex to extract all mod-ids from the blob, from the format "packageId: {modIdentifier}"
	$regex = [regex]::Matches($blob, 'packageId: (.+)[\)\}]')
	$modIdentifiers = $regex | ForEach-Object { $_.Groups[1].Value }
	$modIdentifiersXml = "<li>$($modIdentifiers -join "</li><li>")</li>"

	ReadHost "Found $($modIdentifiers.Count) mods, continue?"
	$modFile = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\ModsConfig.xml"
	$modFileXml = [xml](Get-Content $modFile -Encoding UTF8)
	$modFileXml.ModsConfigData.activeMods.set_InnerXML($modIdentifiersXml)
	$modFileXml.Save($modFile)
	$applicationPath = $settings.steam_path
	$arguments = "-applaunch 294100"
	Stop-RimWorld
	Set-RimworldRunMode -testing
	Start-Process -FilePath $applicationPath -ArgumentList $arguments
}


function Get-ModsInBlob {
	param(
		$blob,
		[switch]$waitForDownload
	)

	# Uses regex to extract all mod-ids from the blob, from the format "id={modId}"
	$regex = [regex]::Matches($blob, 'id=(\d+)')
	$modIds = $regex | ForEach-Object { $_.Groups[1].Value }

	ReadHost "Found $($modIds.Count) mods, continue?"

	$total = $modIds.Count
	$progressObject = WriteProgress -initiate -title "Downloading mods" -totalActions $total
	$downloaded = 0
	$modIds | ForEach-Object {
		WriteProgress -progressObject $progressObject
		$modId = $_
		$modContentPath = "$localModFolder\..\..\..\workshop\content\294100\$modId"
		if (Test-Path "$modContentPath\About\About.xml") {
			WriteMessage -progress "Mod $modId already exists"
			return
		}

		if ($modlist.PSObject.Properties.Value.modId -contains $modId) {
			WriteMessage -progress "Mod $modId is mine, will not download"
			return
		}

		WriteMessage -progress "Downloading mod $modId"
		Set-ModSubscription -modId $modId -subscribe $true -noVerify | Out-Null
		$downloaded++
	}
	WriteProgress -progressObject $progressObject -finished
	WriteMessage -success "Downloaded $downloaded mods"

	if (-not $waitForDownload) {
		return
	}
	WriteMessage -progress "Waiting for download to finish"
	$logPath = "${env:ProgramFiles(x86)}\Steam\logs\content_log.txt"
	$wait = $true
	while ($wait) {
		Start-Sleep -Seconds 10
		$lastLine = Get-Content -Path $logPath -Tail 1
		if ($lastLine -match "scheduler finished") {
			$wait = $false
		}
	}

}

function Set-RimworldRunMode {
	param (
		$prefsFile = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\Prefs.xml",
		[Parameter()][ValidateSet('None', 'Royalty', 'Ideology', 'Biotech', 'Anomaly', 'Odyssey')]
		[string]$skipDLC,
		[switch]$testing,
		[switch]$autoTesting
	)
	if (-not (Test-Path $prefsFile)) {
		WriteMessage -failure "Found no prefs-file at $prefsFile"
		return
	}
	if (-not $skipDLC) {
		$skipDLC = "None"
	}
	$prefsContent = Get-Content $prefsFile -Raw -Encoding UTF8

	if ($testing) {
		$prefsContent = $prefsContent.Replace("<devMode>False</devMode>", "<devMode>True</devMode>")
		$prefsContent = $prefsContent.Replace("<resetModsConfigOnCrash>True</resetModsConfigOnCrash>", "<resetModsConfigOnCrash>False</resetModsConfigOnCrash>")
		$prefsContent = $prefsContent.Replace("<volumeMusic>$($settings.playing_music_volume)</volumeMusic>", "<volumeMusic>$($settings.modding_music_volume)</volumeMusic>")
		$prefsContent = $prefsContent.Replace("<screenWidth>$($settings.playing_screen_witdh)</screenWidth>", "<screenWidth>$($settings.modding_screen_witdh)</screenWidth>")
		$prefsContent = $prefsContent.Replace("<screenHeight>$($settings.playing_screen_height)</screenHeight>", "<screenHeight>$($settings.modding_screen_height)</screenHeight>")
		$prefsContent = $prefsContent.Replace("<fullscreen>True</fullscreen>", "<fullscreen>False</fullscreen>")
		$prefsContent = $prefsContent.Replace("<testMapSizes>False</testMapSizes>", "<testMapSizes>True</testMapSizes>")
	} elseif ($autoTesting) {
		$prefsContent = $prefsContent.Replace("<devMode>False</devMode>", "<devMode>True</devMode>")
		$prefsContent = $prefsContent.Replace("<volumeMusic>$($settings.playing_music_volume)</volumeMusic>", "<volumeMusic>$($settings.modding_music_volume)</volumeMusic>")
		$prefsContent = $prefsContent.Replace("<screenWidth>$($settings.playing_screen_witdh)</screenWidth>", "<screenWidth>$($settings.modding_screen_witdh)</screenWidth>")
		$prefsContent = $prefsContent.Replace("<screenHeight>$($settings.playing_screen_height)</screenHeight>", "<screenHeight>$($settings.modding_screen_height)</screenHeight>")
		$prefsContent = $prefsContent.Replace("<fullscreen>True</fullscreen>", "<fullscreen>False</fullscreen>")
		$prefsContent = $prefsContent.Replace("<testMapSizes>False</testMapSizes>", "<testMapSizes>True</testMapSizes>")
	} else {
		$prefsContent = $prefsContent.Replace("<devMode>True</devMode>", "<devMode>False</devMode>")
		$prefsContent = $prefsContent.Replace("<volumeMusic>$($settings.modding_music_volume)</volumeMusic>", "<volumeMusic>$($settings.playing_music_volume)</volumeMusic>")
		$prefsContent = $prefsContent.Replace("<screenWidth>$($settings.modding_screen_witdh)</screenWidth>", "<screenWidth>$($settings.playing_screen_witdh)</screenWidth>")
		$prefsContent = $prefsContent.Replace("<screenHeight>$($settings.modding_screen_height)</screenHeight>", "<screenHeight>$($settings.playing_screen_height)</screenHeight>")
		$prefsContent = $prefsContent.Replace("<fullscreen>False</fullscreen>", "<fullscreen>True</fullscreen>")
		$prefsContent = $prefsContent.Replace("<testMapSizes>True</testMapSizes>", "<testMapSizes>False</testMapSizes>")
	}
	$prefsContent | Set-Content $prefsFile -Encoding utf8

	$inactiveDlcFolder = "$($settings.rimworld_folder_path)\InactiveDLC"
	$activeDlcFolder = "$($settings.rimworld_folder_path)\Data"
	if ($skipDLC -eq "None") {
		# Move any inactive DLC folders to the Data-folder in the RimWorld-folder
		Get-ChildItem $inactiveDlcFolder -Directory | ForEach-Object {
			$dlcName = $_.Name
			WriteMessage -progress "Moving DLC $dlcName to active folder"
			Move-Item $_.FullName "$activeDlcFolder\$dlcName" -Force
		}
	} else {
		# Test if the DLC is in the active folder, if so, move it to inactive
		if (Test-Path "$activeDlcFolder\$skipDLC") {
			WriteMessage -progress "Moving DLC $skipDLC to inactive folder"
			Move-Item "$activeDlcFolder\$skipDLC" $inactiveDlcFolder -Force
		} else {
			WriteMessage -warning "DLC $skipDLC not found in active folder, skipping"
		}
	}
}

# Stops rimworld and waits for steam to sync after
function Stop-RimWorld {
	[CmdletBinding()]
	param()
	if (-not (Get-Process -Name "RimWorldWin64" -ErrorAction SilentlyContinue)) {
		return
	}

	Stop-Process -Name "RimWorldWin64" -ErrorAction SilentlyContinue
	while ((Get-ItemProperty HKCU:\Software\Valve\Steam -Name RunningAppID).RunningAppID -ne 0) {
		Start-Sleep -Milliseconds 250
	}
	Start-Sleep -Milliseconds 250
	$syncLogPath = "$(Split-Path $settings.steam_path)\logs\cloud_log.txt"
	while ((Get-Item -Path $syncLogPath).LastWriteTime -gt (Get-Date).AddSeconds(-1)) {
		Start-Sleep -Milliseconds 250
	}

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
	param (
		[switch]$play,
		$modObject,
		[string]$testMod,
		[string]$testAuthor,
		[switch]$alsoLoadBefore,
		[Parameter()][ValidateSet('1.0', '1.1', '1.2', '1.3', '1.4', '1.5', '1.6', 'beta', 'speed')]$version,
		$otherModid,
		$mlieMod,
		[Parameter()][ValidateSet('None', 'Royalty', 'Ideology', 'Biotech', 'Anomaly', 'Odyssey')]
		[string]$skipDLC,
		[switch]$autotest,
		[switch]$force,
		[switch]$bare
	)

	if ($test -and $play) {
		WriteMessage -failure "You cant test and play at the same time."
		return
	}
	if (-not $oldRimworldFolder -and $version -ne "beta") {
		WriteMessage -failure "No old RimWorld-folder defined, cannot start old version."
		return
	}
	if ($version -and $version -ne "beta" -and -not ($play -or $testMod -or $modObject)) {
		WriteMessage -failure "Only testing or playing is supported for old versions of RimWorld"
		return
	}
	if ($inBeta -and -not $version) {
		$version = Get-CurrentRimworldVersion
	}
	if (-not $skipDLC) {
		$skipDLC = "None"
	}

	Write-Verbose "Starting RimWorld with version $version"
	$prefsFile = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\Prefs.xml"
	$modFile = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\ModsConfig.xml"
	if ($version -and $version -ne "beta" -and $version -ne (Get-CurrentRimworldVersion)) {
		$oldVersions = Get-ChildItem $oldRimworldFolder -Directory | Select-Object -ExpandProperty Name
		if (-not $oldVersions.Contains($version)) {
			WriteMessage -failure "No RimWorld-folder matching version $version found in $oldRimworldFolder."
			return
		}
		$prefsFile = "$oldRimworldFolder\$version\DataFolder\Config\Prefs.xml"
		$modFile = "$oldRimworldFolder\$version\DataFolder\Config\ModsConfig.xml"
		$testModFile = "$oldRimworldFolder\ModsConfig_$version.xml"
		$oldModFolder = "$oldRimworldFolder\$version\Mods"
	} else {
		$currentActiveMods = Get-Content $modFile -Encoding UTF8
		if ($currentActiveMods.Length -gt 50) {
			$currentActiveMods | Set-Content -Path $playingModsConfig -Encoding UTF8
		} else {
			$currentActiveMods | Set-Content -Path $moddingModsConfig -Encoding UTF8
		}
	}

	Stop-RimWorld

	if ($testAuthor) {
		Copy-Item $testingModsConfig $modFile -Confirm:$false
		if ($autotest) {
			Copy-Item $autoModsConfig $modFile -Confirm:$false
		}
		if ($bare) {
			Copy-Item $bareModsConfig $modFile -Confirm:$false
		}
		$modsList = Get-Content $modFile -Raw -Encoding UTF8
		$modsToTest = Get-AllModsFromAuthor -author $testAuthor -onlyPublished
		$modIdentifiersPrereq = ""
		$modIdentifiers = ""
		foreach ($modname in $modsToTest) {
			$modObject = Get-Mod -modName $modname
			if ($alsoLoadBefore) {
				$identifiersToAdd = Get-IdentifiersFromMod -modObject $modObject -alsoLoadBefore
			} else {
				$identifiersToAdd = Get-IdentifiersFromMod -modObject $modObject
			}
			if ($identifiersToAdd.Length -eq 0) {
				WriteMessage -failure "No mod identifiers found, exiting."
				continue
			}
			if ($identifiersToAdd.Count -eq 1) {
				if ($modIdentifiersPrereq.Contains($identifiersToAdd) -or $modIdentifiers.Contains($identifiersToAdd) -or $modsList -match "<li>$identifiersToAdd</li>") {
					WriteMessage -progress "$identifiersToAdd already in modlist, skipping"
					continue
				}
				WriteMessage -progress "Adding $identifiersToAdd as mod to test"
				$modIdentifiers += "<li>$identifiersToAdd</li>"
			} else {
				foreach ($identifier in $identifiersToAdd) {
					if ($modIdentifiersPrereq.Contains($identifier) -or $modIdentifiers.Contains($identifier) -or $modsList -match "<li>$identifier</li>") {
						continue
					}
					if ($identifier.Contains("ludeon")) {
						continue
					}
					if ($identifier -eq $identifiersToAdd[$identifiersToAdd.Length - 1]) {
						WriteMessage -progress "Adding $identifier as mod to test"
						$modIdentifiers += "<li>$identifier</li>"
					} else {
						WriteMessage -progress "Adding $identifier as prerequirement"
						$modIdentifiersPrereq += "<li>$identifier</li>"
					}
				}
			}
		}
		if ($rimThreaded) {
			WriteMessage -progress "Adding RimThreaded last"
			$modIdentifiers += "<li>majorhoff.rimthreaded</li>"
		}
		$modsList.Replace("</activeMods>", "$modIdentifiersPrereq</activeMods>").Replace("</activeMods>", "$modIdentifiers</activeMods>") | Set-Content $modFile
		Set-RimworldRunMode -prefsFile $prefsFile -testing:(-not $autotest) -autoTesting:$autotest -skipDLC $skipDLC
	}
	if ($testMod) {
		$modObject = Get-Mod -modName $testMod
	}
	if ($modObject) {
		if ((-not $force) -and -not $modObject.Mine) {
			WriteMessage -failure "Not my mod, exiting."
			return
		}
		if ($version -and $version -ne "beta" -and $version -ne (Get-CurrentRimworldVersion)) {
			Copy-Item $testModFile $modFile -Confirm:$false
			$excludes = ".git","Source"
			if ($version -eq "1.0") {
				$identifiersToAdd = Get-IdentifiersFromMod -modObject $modObject -oldmod
			} else {
				$identifiersToAdd = Get-IdentifiersFromMod -modObject $modObject -gameVersion $version -alsoLoadBefore:$alsoLoadBefore
				if ($identifiersToAdd.GetType().Name -eq "String") {
					$identifiersToAdd = @($identifiersToAdd)
				}
				if ($autotest) {
					# Add identifiers for the autotester and spawnmodcontent at the top of the list
					$identifiersToAdd = @("mlie.autotester", "mlie.spawnmodcontent") + $identifiersToAdd
				}
				if ($mlieMod) {
					$otherModid = $mlieMod
				}
				if ($otherModid) {
					if ($alsoLoadBefore) {
						$extraIdentifiersToAdd = Get-IdentifiersFromMod -modId $otherModid -alsoLoadBefore
					} else {
						$extraIdentifiersToAdd = Get-IdentifiersFromMod -modId $otherModid
					}
					$combinedIdentifiers = @()
					if ($identifiersToAdd.Count -gt 1) {
						for ($i = 0; $i -lt $identifiersToAdd.Count - 1; $i++) {
							$combinedIdentifiers += $identifiersToAdd[$i]
						}
					}
					foreach ($id in $extraIdentifiersToAdd) {
						if ($identifiersToAdd -notcontains $id) {
							$combinedIdentifiers += $id
						}
					}
					if ($identifiersToAdd.Count -gt 1) {
						$combinedIdentifiers += $identifiersToAdd[-1]
					} else {
						$combinedIdentifiers += $identifiersToAdd
					}
					$identifiersToAdd = $combinedIdentifiers
				}
			}
			if ($mlieMod) {
				$mlieModFolder = $mlieMod.Split(".")[1]
				if (Test-Path "$oldModFolder\$mlieModFolder") {
					WriteMessage -progress "Removing $mlieModFolder from old rimworld mod-folder"
					Remove-Item -Path "$oldModFolder\$mlieModFolder" -Recurse -Force
				}
				WriteMessage -progress "Copying $mlieModFolder to old rimworld mod-folder"
				Get-ChildItem "$localModFolder\$mlieModFolder" | Where-Object { $_.Name -notin $excludes } | ForEach-Object { Copy-Item -Path $_ -Destination "$oldModFolder\$mlieModFolder\$($_.Name)" -Recurse -Force }
			}
			if (Test-Path "$oldModFolder\$($modObject.Name)") {
				WriteMessage -progress "Removing $($modObject.DisplayName) from old rimworld mod-folder"
				Remove-Item -Path "$oldModFolder\$($modObject.Name)" -Recurse -Force
			}
			WriteMessage -progress "Copying $($modObject.DisplayName) to old rimworld mod-folder"
			Get-ChildItem $modObject.ModFolderPath | Where-Object { $_.Name -notin $excludes } | ForEach-Object { Copy-Item -Path $_ -Destination "$oldModFolder\$($modObject.Name)\$($_.Name)" -Recurse -Force }

			if ($modObject.ManifestFilePath) {
				$modObject.ManifestFileContent.Replace($localModFolder, $oldModFolder) | Set-Content "$oldModFolder\$modname\_PublisherPlus.xml" -Encoding UTF8
			}
		} else {
			Copy-Item $testingModsConfig $modFile -Confirm:$false
			if ($autotest ) {
				Copy-Item $autoModsConfig $modFile -Confirm:$false
			}
			if ($bare) {
				Copy-Item $bareModsConfig $modFile -Confirm:$false
			}
			$modsList = Get-Content $modFile -Raw -Encoding UTF8
			if ($alsoLoadBefore) {
				$identifiersToAdd = Get-IdentifiersFromMod -modObject $modObject -alsoLoadBefore
			} else {
				$identifiersToAdd = Get-IdentifiersFromMod -modObject $modObject
			}
			if ($otherModid) {
				if ($alsoLoadBefore) {
					$extraIdentifiersToAdd = Get-IdentifiersFromMod -modId $otherModid -alsoLoadBefore
				} else {
					$extraIdentifiersToAdd = Get-IdentifiersFromMod -modId $otherModid
				}
				$combinedIdentifiers = @()
				if ($identifiersToAdd.Count -gt 1) {
					for ($i = 0; $i -lt $identifiersToAdd.Count - 1; $i++) {
						$combinedIdentifiers += $identifiersToAdd[$i]
					}
				}
				foreach ($id in $extraIdentifiersToAdd) {
					if ($identifiersToAdd -notcontains $id) {
						$combinedIdentifiers += $id
					}
				}
				if ($identifiersToAdd.Count -gt 1) {
					$combinedIdentifiers += $identifiersToAdd[-1]
				} else {
					$combinedIdentifiers += $identifiersToAdd
				}
				$identifiersToAdd = $combinedIdentifiers
			}
		}
		$modIdentifiers = ""
		if ($identifiersToAdd.Count -eq 1) {
			if ($modsList -notmatch "<li>$identifiersToAdd</li>") {
				WriteMessage -progress "Adding $identifiersToAdd as mod to test"
				$modIdentifiers += "<li>$identifiersToAdd</li>"
			} else {
				WriteMessage -progress "$identifiersToAdd already in modlist, skipping"
			}
		} else {
			foreach ($identifier in $identifiersToAdd) {
				if ($identifier.Contains("ludeon") -or $modsList -match "<li>$identifier</li>") {
					WriteMessage -progress "$identifier already in modlist, skipping"
					continue
				}
				if ($identifier -eq $identifiersToAdd[$identifiersToAdd.Length - 1]) {
					WriteMessage -progress "Adding $identifier as mod to test"
				} else {
					WriteMessage -progress "Adding $identifier as prerequirement"
				}
				$modIdentifiers += "<li>$identifier</li>"
			}
		}
		(Get-Content $modFile -Raw -Encoding UTF8).Replace("</activeMods>", "$modIdentifiers</activeMods>") | Set-Content $modFile
		Set-RimworldRunMode -prefsFile $prefsFile -testing:(-not $autotest) -autoTesting:$autotest -skipDLC $skipDLC
	}
	if ($play) {
		if (-not $version -or $version -eq "beta") {
			Copy-Item $playingModsConfig $modFile -Confirm:$false
		}
		Set-RimworldRunMode -prefsFile $prefsFile -skipDLC $skipDLC
	}
	if ($bare) {
		if (-not $modObject -and -not $testMod -and -not $testAuthor) {
			Copy-Item $bareModsConfig $modFile -Confirm:$false
		}
		Set-RimworldRunMode -prefsFile $prefsFile -skipDLC $skipDLC
	}
	if (-not $testMod -and -not $modObject -and -not $play -and -not $bare -and -not $testAuthor ) {
		Copy-Item $moddingModsConfig $modFile -Confirm:$false
		Set-RimworldRunMode -prefsFile $prefsFile -testing:(-not $autotest) -autoTesting:$autotest -skipDLC $skipDLC
	}
	Start-Sleep -Seconds 2
	$currentLocation = Get-Location
	if ($version -and $version -ne "beta" -and $version -ne (Get-CurrentRimworldVersion)) {
		$applicationPath = "$oldRimworldFolder\$version\RimWorldWin64.exe"
		$arguments = "-savedatafolder=DataFolder"
		Set-Location "$oldRimworldFolder\$version"
	} else {
		$applicationPath = $settings.steam_path
		$arguments = "-applaunch 294100"
	}
	if ($autotest) {
		$arguments += " -quicktest"
	}
	$startTime = Get-Date
	Start-Process -FilePath $applicationPath -ArgumentList $arguments
	if ($currentLocation -ne (Get-Location)) {
		Set-Location $currentLocation
	}
	if (-not $autotest) {
		return $true
	}
	$logPath = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Player.log"
	while ($true) {
		if ((Get-Item -Path $logPath).LastWriteTime -lt $startTime) {
			Start-Sleep -Seconds 1
			continue
		}

		if (-not (Get-Process -Name "RimWorldWin64" -ErrorAction SilentlyContinue)) {
			break
		}

		if (-not ((Get-Item -Path $logPath).LastWriteTime -ge (Get-Date).AddSeconds(-60))) {
			if (-not (Select-String -Path $logPath -Pattern "Initializing new game with mods")) {
				Start-Sleep -Seconds 1
				continue
			}
			break
		}

		Start-Sleep -Seconds 1
	}
	WriteMessage -progress "Stopping rimworld"
	Stop-RimWorld
	$logContent = Get-Content $logPath -Raw -Encoding UTF8
	if ($logContent.Contains("[[Autotest failed]]")) {
		Copy-Item $logPath "$($modObject.ModFolderPath)\Source\lastrun.log" -Force | Out-Null
		return $false
	}
	if (Test-Path "$($modObject.ModFolderPath)\Source\lastrun.log") {
		Remove-Item "$($modObject.ModFolderPath)\Source\lastrun.log" -Force -Confirm:$false
	}
	return $true
}

# Test the mod in the current directory
function Test-Mod {
	param([Parameter()]
		[ValidateSet('1.0', '1.1', '1.2', '1.3', '1.4', '1.5', '1.6', 'beta', 'speed')]
		[string] $version,
		$otherModid,
		$otherModName,
		[string] [Parameter()][ValidateSet('None', 'Royalty', 'Ideology', 'Biotech', 'Anomaly', 'Odyssey')]
		$skipDLC,
		[switch] $alsoLoadBefore,
		[switch] $autotest,
		[switch] $force,
		[switch] $lastVersion,
		[switch] $bare)

	$modObject = Get-Mod

	if (-not $modObject.ModFolderPath) {
		return
	}

	if (-not $version) {
		$version = Get-CurrentRimworldVersion
	}

	if (-not $skipDLC) {
		$skipDLC = "None"
	}

	if ($otherModName) {
		if ($otherModName.StartsWith("Mlie.") ) {
			$mlieMod = $otherModName
		} else {
			$modLink = Get-ModLink -modName $otherModName -chooseIfNotFound -lastVersion:$lastVersion
			if (-not $modLink -and -not $lastVersion) {
				WriteMessage -progress "Could not find other mod named $otherModName, trying to find the last version"
				$modLink = Get-ModLink -modName $otherModName -chooseIfNotFound -lastVersion:$true
			}
			if (-not $modLink) {
				WriteMessage -failure "Could not find other mod named $otherModName, exiting"
				return
			}
			$otherModid = $modLink.Split('=')[1]
		}
	}

	if ($autotest) {
		WriteMessage -progress "Auto-testing $($modObject.DisplayName)"
	} else {
		WriteMessage -progress "Testing $($modObject.DisplayName)"
	}
	return Start-RimWorld -modObject $modObject -version $version -alsoLoadBefore:$alsoLoadBefore -autotest:$autotest -force:$force -bare:$bare -otherModid $otherModid -mlieMod $mlieMod -skipDLC $skipDLC
}

#endregion

#region Mod-descriptions

# Cleans the mod-description from broken chars
function Set-CleanModDescription {
	param(
		$modObject,
		[switch]$noWait
	)
	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}
	if (-not $modObject.Mine) {
		WriteMessage -failure "$($modObject.Name) is not mine, aborting update"
		return
	}

	if (-not ($modObject.AboutFileContent -match "&apos;") -and `
			-not ($modObject.AboutFileContent -match "&quot;") -and `
			-not ($modObject.AboutFileContent -match "&lt;") -and `
			-not ($modObject.AboutFileContent -match "&gt;")) {
		WriteMessage -progress "Local description for $($modObject.Name) does not need cleaning"
		return
	}
	WriteMessage -success "Starting with $($modObject.Name)"
	Sync-ModDescriptionFromSteam -modObject $modObject
	$modObject = Get-Mod -originalModObject $modObject
	$modObject.AboutFileContent = $modObject.AboutFileContent.Replace("&quot;", '"').Replace("&apos;", "'").Replace("&lt;", "").Replace("&gt;", "")
	$modObject.AboutFileContent | Set-Content -Path $modObject.AboutFilePath -Encoding UTF8
	$modObject.AboutFileXml = [xml]$modObject.AboutFileContent
	Sync-ModDescriptionToSteam -modObject $modObject
	if ($noWait) {
		return
	}
	Get-ModPage -modObject $modObject
	ReadHost "Continue?"
}

# Fetches the description of a mod from steam
function Get-ModDescription {
	param(
		$modId
	)

	$applicationPath = "$($settings.script_root)\SteamDescriptionEdit\Compiled\SteamDescriptionEdit.exe"
	$stagingDirectory = $settings.mod_staging_folder
	$tempDescriptionFile = "$stagingDirectory\tempdesc.txt"
	Remove-Item -Path $tempDescriptionFile -Force -ErrorAction SilentlyContinue
	$arguments = @($modId, "SAVE", $tempDescriptionFile)
	Start-Process -FilePath $applicationPath -ArgumentList $arguments -Wait -NoNewWindow | Out-Null
	if (-not (Test-Path $tempDescriptionFile)) {
		WriteMessage -warning "No description found on steam for $modId"
		return
	}
	$currentDescription = Get-Content -Path $tempDescriptionFile -Raw -Encoding UTF8
	if ($currentDescription.Length -eq 0) {
		WriteMessage -warning "Description found on steam for $modId was empty"
		return
	}

	return $currentDescription
}


# Replaces a string in all descriptions
function Update-ModDescription {
	param(
		[string[]]$searchStrings,
		[string[]]$replaceStrings,
		$modObject,
		[switch]$all,
		[switch]$syncBefore,
		[switch]$mineOnly,
		[switch]$notMine,
		$waittime = 500
	)

	if (-not $searchStrings) {
		WriteMessage -failure "Searchstrings must be defined"
		return
	}
	if (-not $replaceStrings) {
		$result = ReadHost "Replacestring is not defined, continue? (y/n)"
		if ($result -eq "y") {
			return
		}
	} else {
		if ($searchStrings.Count -ne $replaceStrings.Count) {
			WriteMessage -failure "If replacestrings are defined, they must be the same amount as searchstrings"
			WriteMessage -progress "Searchstrings: $($searchStrings.Count): $($searchStrings -join ",")"
			WriteMessage -progress "Replacestrings: $($replaceStrings.Count): $($replaceStrings -join ",")"
			return
		}
	}
	$modFolders = @()
	if (-not $all) {
		if (-not $modObject) {
			$modObject = Get-Mod
			if (-not $modObject) {
				return
			}
		}

		if (-not $modObject.ModFolderPath) {
			WriteMessage -failure "$($modObject.Name) folder can not be found, exiting"
			return
		}
		$modFolders += $modObject.ModFolderPath
	} else {
		(Get-ChildItem -Directory $localModFolder).FullName | ForEach-Object { $modFolders += $_ }
	}

	WriteMessage -success "Will replace $($searchStrings -join ",") with $($replaceStrings -join ",") in $($modFolders.Count) mods"
	$total = $modFolders.Count
	$applicationPath = "$($settings.script_root)\SteamDescriptionEdit\Compiled\SteamDescriptionEdit.exe"
	$progressObject = WriteProgress -initiate -title "Updating mod-descriptions" -totalActions $total
	$totalsearchCharacters = $searchStrings | ForEach-Object { $_.Length } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
	$totalreplaceCharacters = $replaceStrings | ForEach-Object { $_.Length } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
	$difference = $totalreplaceCharacters - $totalsearchCharacters
	$limit = 8000
	WriteMessage -progress "Descriptions are limited to $limit characters on steam, changes will add $difference characters"

	foreach ($folder in ($modFolders | Get-Random -Count $modFolders.Count)) {
		WriteProgress -progressObject $progressObject

		$modObject = Get-Mod $(Split-Path $folder -Leaf)

		if (-not $modObject.Published) {
			WriteMessage -progress "$($modObject.Name) is not published, ignoring"
			continue
		}
		if (-not $modObject.Mine) {
			WriteMessage -progress "$($modObject.Name) is not mine, ignoring"
			continue
		}

		if ($notMine -and -not $modObject.Continued) {
			WriteMessage -progress "$($modObject.Name) is mine, ignoring"
			continue
		}
		if ($mineOnly -and $modObject.Continued) {
			WriteMessage -progress "$($modObject.Name) is not mine, ignoring"
			continue
		}
		if ($syncBefore) {
			Sync-ModDescriptionFromSteam -modObject $modObject
			$modObject = Get-Mod $(Split-Path $folder -Leaf)
		}

		if (($modObject.DescriptionLength + $difference) -gt $limit) {
			WriteMessage -failure "Description for $($modObject.Name) would exceed $limit characters, you need to shorten it by $($modObject.DescriptionLength + $difference - $limit) characters, then press enter"
			Get-ModPage -modObject $modObject
			ReadHost
			Sync-ModDescriptionFromSteam -modObject $modObject
			$modObject = Get-Mod $(Split-Path $folder -Leaf)
			while (($modObject.DescriptionLength + $difference) -gt $limit) {
				WriteMessage -failure "Description for $($modObject.Name) still exceeds $limit characters, you need to shorten it by $($modObject.DescriptionLength + $difference - $limit) characters, then press enter"
				ReadHost
				Sync-ModDescriptionFromSteam -modObject $modObject
				$modObject = Get-Mod $(Split-Path $folder -Leaf)
			}
		}

		$anythingChanged = $false
		for ($i = 0; $i -lt $searchStrings.Count; $i++) {
			$searchString = $searchStrings[$i]
			$searchStringEscaped = [Regex]::Escape($searchString)

			if ($replaceStrings) {
				$replaceString = $replaceStrings[$i]
				$replaceStringEscaped = [Regex]::Escape($replaceString)
			}
			if ($replaceStrings -and (Select-String -InputObject $modObject.AboutFileXml.ModMetaData.description -pattern $replaceStringEscaped)) {
				WriteMessage -progress "Description for $($modObject.Name) already contains the replace-string, skipping"
				continue
			}
			if (Select-String -InputObject $modObject.AboutFileXml.ModMetaData.description -pattern $searchStringEscaped) {
				Start-Sleep -Milliseconds $waittime
				$arguments = @($modObject.PublishedId, "REPLACE", """$searchString""", """$replaceString""")
				Start-Process -FilePath $applicationPath -ArgumentList $arguments -Wait -NoNewWindow
				$anythingChanged = $true
			} else {
				WriteMessage -progress "Description for $($modObject.Name) does not contain $searchString"
			}
		}

		if ($anythingChanged) {
			Sync-ModDescriptionFromSteam -modObject $modObject
			WriteMessage -success "Updated description for $($modObject.Name)"
		} else {
			WriteMessage -progress "No changes made to description for $($modObject.Name)"
		}
	}
	WriteProgress -progressObject $progressObject -finished
}

# Replaces the decsription with what is set on the steam-page
function Sync-ModDescriptionFromSteam {
	param(
		$modObject,
		[switch]$Force
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not $modObject.ModFolderPath) {
		WriteMessage -failure "Mod folder can not be found, exiting"
		return
	}

	if (-not $Force -and -not $modObject.Mine) {
		WriteMessage -failure "$($modObject.Name) is not mine, aborting sync"
		return
	}
	if (-not $modObject.Published) {
		WriteMessage -failure "$($modObject.Name) not published, aborting sync"
		return
	}

	$applicationPath = "$($settings.script_root)\SteamDescriptionEdit\Compiled\SteamDescriptionEdit.exe"
	$stagingDirectory = $settings.mod_staging_folder
	$tempDescriptionFile = "$stagingDirectory\tempdesc.txt"
	Remove-Item -Path $tempDescriptionFile -Force -ErrorAction SilentlyContinue
	$arguments = @($modObject.PublishedId, "SAVE", $tempDescriptionFile)
	Start-Process -FilePath $applicationPath -ArgumentList $arguments -Wait -NoNewWindow
	if (-not (Test-Path $tempDescriptionFile)) {
		WriteMessage -failure "No description found on steam for $($modObject.Name), aborting sync"
		return
	}
	$currentDescription = Get-Content -Path $tempDescriptionFile -Raw -Encoding UTF8
	if ($currentDescription.Length -eq 0) {
		WriteMessage -failure "Description found on steam for $($modObject.Name) was empty, aborting sync"
		return
	}

	$modObject.AboutFileXml.ModMetaData.description = $currentDescription.Replace(" & ", " &amp; ").Replace(">", "").Replace("<", "")
	$modObject.AboutFileXml.Save($modObject.AboutFilePath)
	$modObject.AboutFileContent = Get-Content $modObject.AboutFilePath -Raw -Encoding UTF8
	$modObject.Description = $modObject.AboutFileXml.ModMetaData.description
	return
}

# Replaces the steam mod-description with the local description
function Sync-ModDescriptionToSteam {
	param(
		$modObject,
		[switch]$Force
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not $modObject.ModFolderPath ) {
		WriteMessage -failure "$($modObject.ModFolderPath) can not be found, exiting"
		return
	}
	if (-not $Force -and -not $modObject.Mine) {
		WriteMessage -failure "$($modObject.Name) is not mine, aborting sync"
		return
	}
	if (-not $modObject.Published) {
		WriteMessage -failure "$($modObject.Name) not published, aborting sync"
		return
	}

	$applicationPath = "$($settings.script_root)\SteamDescriptionEdit\Compiled\SteamDescriptionEdit.exe"
	$stagingDirectory = $settings.mod_staging_folder
	$tempDescriptionFile = "$stagingDirectory\tempdesc.txt"

	$modObject.Description | Set-Content -Path $tempDescriptionFile -Encoding UTF8
	$arguments = @($modObject.PublishedId, "SET", $tempDescriptionFile)
	Start-Process -FilePath $applicationPath -ArgumentList $arguments -Wait -NoNewWindow
	return
}

# Function to generate search-tags in the description
function Update-ModDescriptionTags {
	param(
		$modObject,
		[switch]$silent,
		[switch]$force
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not $modObject.Mine) {
		WriteMessage -failure "$($modObject.Name) is not mine, aborting update"
		return
	}

	if ($modObject.MetadataFileJson.SearchTags -and -not $force) {
		WriteMessage -progress "Search-tags already set for $($modObject.Name), skipping"
		return
	}

	$prompt = @"
Generate up to five search tags for the following Rimworld mod description.
These should make it easier for users to find the mod in the workshop and should not be too generic.
They should not contain the words: Rimworld, Update, Game, Mod, Discord, Forum, Translation, Version, Steam, Workshop, Ludeon, Studios, Author, Name, Description, Features, Research
They should not contain any of the words in the description itself.
Return them in a comma-separated list.

Description: $($modObject.Name)
$($modObject.DescriptionClean)

Tags:
"@

	$body = @{
		"model"      = $openAIModel
		"prompt"     = $prompt
		"max_tokens" = 50
	} | ConvertTo-Json

	$headers = @{
		"Content-Type"  = "application/json"
		"Authorization" = "Bearer $openAIApiKey"
	}
	$tags = @()
	try {
		$response = Invoke-RestMethod -Uri "https://api.openai.com/v1/completions" -Method Post -Headers $headers -Body $body
		$tags = $response.choices.text.ToLower().Trim().Replace('"', "") -split ","
	} catch {
		WriteMessage -failure "Failed to generate search-tags for $($modObject.Name)`nError: $_"
		if ($silent) {
			return
		}
	}

	if ($tags.Length -eq 0) {
		$tags = ReadHost "No tags genererated, enter tags separated by comma"
		$tags = $tags -split ","
		$silent = $true
	}

	if (-not $silent) {
		WriteMessage -progress $modObject.ModUrl
		$tagsAsNumberedList = @()
		for ($i = 0; $i -lt $tags.Length; $i++) {
			$tagsAsNumberedList += "$($i + 1). $($tags[$i].Trim())"
		}
		$answer = ReadHost "$($tagsAsNumberedList -join "`n")`n`nDo you want to update the description with these tags? `nEnter to continue, n to cancel, m to modify, numbers separated by space to select tags.`n"
		if ($answer -eq "n") {
			return
		}
		if ($answer -eq "m") {
			$tags = ReadHost "Enter tags separated by comma"
			$tags = $tags -split ","
		}
		if ($answer -match "\d") {
			$tags = $answer -split " " | ForEach-Object { $tags[$_ - 1] }
		}
	}
	if (-not $modObject.MetadataFileJson.PSObject.Properties.Name.Contains("SearchTags")) {
		$modObject.MetadataFileJson | Add-Member -NotePropertyName "SearchTags" -NotePropertyValue $tags
	} else {
		$modObject.MetadataFileJson.SearchTags = $tags
	}
	$modObject.MetadataFileJson | ConvertTo-Json | Set-Content -Path $modObject.MetadataFilePath -Force
	WriteMessage -success "Updated search-tags for $($modObject.Name)"
}

function Update-ModCopilotMetadata {
	param(
		$modObject,
		[switch]$force
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not $modObject.Mine) {
		WriteMessage -failure "$($modObject.Name) is not mine, aborting update"
		return
	}

	if (-not $modObject.HasAssemblies) {
		WriteMessage -progress "Mod has no assemblies $($modObject.Name)"
		return
	}

	# Define paths
	$sourcePath = Join-Path $modObject.ModFolderPath "Source"
	$xmlSourcePath = Join-Path $modObject.ModFolderPath "Defs"
	if (-not (Test-Path $xmlSourcePath)) {
		$xmlSourcePath = Join-Path $modObject.ModFolderPath $modObject.HighestSupportedVersion "Defs"
	}
	$githubPath = Join-Path $modObject.ModFolderPath ".github"
	$instructionsPath = Join-Path $githubPath "copilot-instructions.md"

	if (-not $force -and (Test-Path $instructionsPath)) {
		if (-not (Get-Content -Raw $instructionsPath).Contains($modObject.DisplayName)) {
			WriteMessage -progress "copilot-instructions.md exists but does not contain the required content, updating"
		} else {
			WriteMessage -progress "copilot-instructions.md already exists, skipping update"
			return
		}
	}

	WriteMessage -progress "Generating copilot-instructions.md for $($modObject.Name)"
	# Summarize C# files
	$csSummary = Get-ChildItem -Path $sourcePath -Recurse -Include *.cs -ErrorAction SilentlyContinue | ForEach-Object {
		$content = Get-Content $_.FullName -Raw
		$classes = ($content -split "`n") | Where-Object { $_ -match 'class\s+\w+' }
		$methods = ($content -split "`n") | Where-Object { $_ -match '\b(public|private|protected|internal)\s+\w+\s+\w+\(' }
		"File: $($_.Name)`nClasses:`n$($classes -join "`n")`nMethods:`n$($methods -join "`n")`n"
	}

	# Construct prompt
	$prompt = @"
You are an assistant that generates GitHub Copilot instruction files for RimWorld modding projects in C#.
Based on the following summarized content from a mod project, generate a detailed .github/copilot-instructions.md file that includes:

- Mod overview and purpose
- Key features and systems
- Coding patterns and conventions
- XML integration
- Harmony patching
- Suggestions for Copilot

Mod Name: $($modObject.DisplayName)
Mod Description: $($modObject.DescriptionClean)

C# Summary:
$csSummary
"@

	# Prepare request
	$headers = @{ "Authorization" = "Bearer $openAIApiKey" }
	$body = @{
		model    = $openAIChatModel
		messages = @(
			@{ role = "system"; content = "You are a helpful assistant for game mod developers." },
			@{ role = "user"; content = $prompt }
		)
	}
	$jsonBody = $body | ConvertTo-Json -Depth 10

	# Send request
	$response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Headers $headers -Body $jsonBody -ContentType "application/json"

	# Save result
	if (-not (Test-Path $githubPath)) {
		New-Item -ItemType Directory -Path $githubPath | Out-Null
	}
	$response.choices[0].message.content | Set-Content -Path $instructionsPath

	# Remove any ```markdown code blocks and ``` lines
	$instructionsContent = Get-Content -Path $instructionsPath -Raw
	$instructionsContent = $instructionsContent -replace '```markdown', '' -replace '```', ''
	$instructionsContent = $instructionsContent.Trim()
	$instructionsContent | Set-Content -Path $instructionsPath -Encoding UTF8

	WriteMessage -success "copilot-instructions.md created at $instructionsPath"
}

function Update-MissingItemDescriptions {
	[CmdletBinding()]
	param (
		[string]$filePath,
		[string]$folderPath,
		[string]$itemType
	)

	if (-not $filePath -and -not $folderPath) {
		WriteMessage -failure "A path must be provided"
		return
	}
	if ($filePath -and $folderPath) {
		WriteMessage -failure "Only one path must be provided"
		return
	}
	if ($filePath) {
		if (-not (Test-Path $filePath)) {
			WriteMessage -failure "File $filePath does not exist"
			return
		}
		$xmlFiles = @((Get-Item -Path $filePath) )
	} elseif ($folderPath) {
		if (-not (Test-Path $folderPath)) {
			WriteMessage -failure "Folder $folderPath does not exist"
			return
		}
		$xmlFiles = Get-ChildItem -Path $folderPath -Recurse -Include *.xml
	}

	foreach ($xmlFile in $xmlFiles) {
		[xml]$xmlContent = Get-Content -Path $xmlFile.FullName -Raw
		# Select ThingDef with a description node that is less than 5 characters long or empty
		$items = $xmlContent.SelectNodes("//ThingDef[description and (string-length(description) < 5 or description = '')]")
		foreach ($item in $items) {
			$itemName = $item.label
			if (-not $itemName) {
				continue
			}
			WriteMessage -progress "Generating description for $itemName in $($xmlFile.Name)"
			if (-not $itemType) {
				$currentItemType = ReadHost "Item type not provided, enter item type for $itemName or empty for default (item)"
			} else {
				$currentItemType = $itemType
			}
			$description = Get-ItemDescription -itemName $itemName -itemType $currentItemType
			if ($description) {
				$item.description = $description
				WriteMessage -success "Updated description for $itemName"
			} else {
				WriteMessage -warning "Failed to generate description for $itemName"
			}
		}
		$xmlContent.Save($xmlFile.FullName)
	}
}

function Get-ItemDescription {
	param(
		[string]$itemName,
		[string]$itemType = "item" # item, weapon, apparel, building, furniture, etc.
	)

	if (-not $itemName) {
		WriteMessage -failure "Item name must be provided"
		return
	}

	$prompt = @"
You are an assistant that provides detailed descriptions for items in the game RimWorld.
Given the item name, provide a concise yet informative description suitable for a the info card in the game.
Item Name: $itemName
Item Type: $itemType

Please only provide the description text without any additional commentary.
"@
	# Prepare request
	$headers = @{ "Authorization" = "Bearer $openAIApiKey" }
	$body = @{
		model    = $openAIChatModel
		messages = @(
			@{ role = "system"; content = "You are a helpful assistant for game mod developers." },
			@{ role = "user"; content = $prompt }
		)
	}
	$jsonBody = $body | ConvertTo-Json -Depth 10

	# Send request
	$response = Invoke-RestMethod -Uri "https://api.openai.com/v1/chat/completions" -Method Post -Headers $headers -Body $jsonBody -ContentType "application/json"

	# Save result
	return $response.choices[0].message.content
}

#endregion

#region Publishing functions

# Function for pushing new version of mod to git-repo
# On first publish adds gitignore-file, PublisherPlus-file, Licence
# Updates the Manifest, ModSyncfile with new version
# Downloads the current git-hub version to a staging directory
# Copies the current version of the mod to the staging directory
# Pushes the updated source to github and generates a new release
function Publish-Mod {
	[CmdletBinding()]
	param (
		[switch]$SkipNotifications,
		[switch]$GithubOnly,
		[string]$ChangeNote,
		[string]$ExtraInfo,
		[string]$Comment,
		[string]$ReplacedBy,
		[switch]$EndOfLife,
		[switch]$Deprecated,
		[switch]$Abandoned,
		[switch]$Force,
		[switch]$Auto,
		[switch]$ReRelease,
		[switch]$Replacement,
		[switch]$Silent
	)

	$modObject = Get-Mod
	$skipInteraction = $EndOfLife -or $Deprecated -or $Abandoned -or $ReplacedBy -or $ReRelease
	if ($ReRelease) {
		$SkipNotifications = $true
	}

	if (-not $modObject) {
		WriteMessage -failure "Current path is not a mod-folder, aborting publish"
		return
	}

	if (-not $Force -and -not $modObject.Mine) {
		WriteMessage -failure "$($modObject.Name) is not mine, aborting publish"
		return
	}

	SetTerminalProgress -unknown
	$stagingDirectory = $settings.mod_staging_folder
	$reapplyGitignore = $false
	$gitApiToken = $settings.github_api_token

	# Clean up XML-files
	if (-not (Set-ModXml)) {
		WriteMessage -failure "Could not clean up XML-files, aborting publish"
		return
	}

	while (-not $modObject.PreviewFilePath) {
		ReadHost "Preview-file does not exist, create one then press Enter"
		$modObject = Get-Mod
	}

	if ((Get-Item $modObject.PreviewFilePath).Length -ge 1MB) {
		WriteMessage -warning "Preview-file is too large, resizing"
		Set-ImageSizeBelow -imagePath $modObject.PreviewFilePath -sizeInKb 999 -removeOriginal
	}

	# Remove leftover-files
	if (Test-Path "$($modObject.ModFolderPath)\Source\lastrun.log") {
		Remove-Item "$($modObject.ModFolderPath)\Source\lastrun.log" -Force
	}

	# Auto-translate files if needed
	if (-not $skipInteraction) {
		$extraCommitInfo = Update-Translations -modObject $modObject -silent -force:$Force
		Get-ChildItem $($modObject.ModFolderPath) -File -Recurse -Filter *.xml | Where-Object { $_.FullName -match "Languages\\ChineseSimplified" } | ForEach-Object { (Get-Content $_.FullName -Encoding utf8).Replace("已安装的mod-version。{0}", "已安装的模组版本：{0}") | Set-Content $_.FullName }
		Set-ModXml
	}

	# Mod Manifest
	if (-not $modObject.ManifestFilePath) {
		$modObject.ManifestFilePath = "$($modObject.ModFolderPath)\About\Manifest.xml"
		Copy-Item -Path $manifestTemplate $modObject.ManifestFilePath -Force | Out-Null
		((Get-Content -path $modObject.ManifestFilePath -Raw -Encoding UTF8).Replace("[modname]", $modObject.NameClean).Replace("[username]", $settings.github_username)) | Set-Content -Path $modObject.ManifestFilePath -Encoding UTF8
		$modObject.ManifestFileContent = Get-Content $modObject.ManifestFilePath -Raw -Encoding UTF8
		$modObject.ManifestFileXml = [xml]$modObject.ManifestFileContent
		$version = Get-NextVersionNumber -currentVersion $modObject.HighestSupportedVersion -referenceVersion $modObject.HighestSupportedVersion
		$modObject.ManifestFileXml.Manifest.version = $version.ToString()
		$modObject.ManifestFileXml.Save($modObject.ManifestFilePath)
		$modObject.ManifestFileContent = Get-Content $modObject.ManifestFilePath -Raw -Encoding UTF8
	} else {
		$currentIdentifier = $modObject.ManifestFileXml.Manifest.identifier
		$version = [version]$modObject.ManifestFileXml.Manifest.version
		if ($currentIdentifier -ne $modObject.NameClean) {
			$modObject.ManifestFileXml.Manifest.identifier = $modObject.NameClean
			$modObject.ManifestFileXml.Save($modObject.ManifestFilePath)
			$modObject.ManifestFileContent = Get-Content $modObject.ManifestFilePath -Raw -Encoding UTF8
		}
	}
	if (Test-Path $licenseFile) {
		if (Test-Path "$($modObject.ModFolderPath)\LICENSE") {
			Remove-Item -Path "$($modObject.ModFolderPath)\LICENSE" -Force
		}
		if (-not $modObject.LicensePath) {
			$modObject.LicensePath = "$($modObject.ModFolderPath)\LICENSE.md"
			Copy-Item -Path $licenseFile $modObject.LicensePath -Force | Out-Null
		} else {
			if ((Get-Item -Path $modObject.LicensePath).LastWriteTime -lt (Get-Item $licenseFile).LastWriteTime) {
				WriteMessage "Updating Licence file for $($modObject.Name)"
				Copy-Item -Path $licenseFile $modObject.LicensePath -Force | Out-Null
			}
		}
	}
	if (-not $modObject.GitIgnorePath -or ((Get-Item $gitignoreTemplate).LastWriteTime -gt (Get-Item $modObject.GitIgnorePath).LastWriteTime)) {
		$modObject.GitIgnorePath = "$($modObject.ModFolderPath)\.gitignore"
		WriteMessage "Updating gitignore file for $($modObject.Name)"
		Copy-Item -Path $gitignoreTemplate $modObject.GitIgnorePath -Force | Out-Null
		$reapplyGitignore = $true
	}
	if ((Test-Path $modSyncTemplate) -and -not $modObject.ModSyncFilePath) {
		$modObject.ModSyncFilePath = "$($modObject.ModFolderPath)\About\ModSync.xml"
		New-ModSyncFile -modObject $modObject -version $version.ToString()
	}
	if ((Test-Path $publisherPlusTemplate) -and (-not $modObject.ModPublisherPath -or (Get-Item $publisherPlusTemplate).LastWriteTime -gt (Get-Item $modObject.ModPublisherPath).LastWriteTime)) {
		$modObject.ModPublisherPath = "$($modObject.ModFolderPath)\_PublisherPlus.xml"
		Copy-Item -Path $publisherPlusTemplate $modObject.ModPublisherPath -Force | Out-Null
		((Get-Content -path $modObject.ModPublisherPath -Raw -Encoding UTF8).Replace("[modpath]", $modObject.ModFolderPath)) | Set-Content -Path $modObject.ModPublisherPath
	}
	if ($modObject.UsesAssetBundle) {
		Update-ModAssetBundle -modObject $modObject -update
	}

	# Create repo if does not exists
	if ((Get-RepositoryStatus -repositoryName $modObject.NameClean) -eq $true) {
		if ($ChangeNote) {
			$message = $ChangeNote
		} elseif ($skipInteraction) {
			$message = "Last update, added end-of-life message"
		} else {
			$message = Get-MultilineMessage -query "Changenote" -mustFill
		}
		$oldVersion = $version.ToString()
		$newVersion = (Get-NextVersionNumber -currentVersion $version -referenceVersion $modObject.HighestSupportedVersion).ToString()
		((Get-Content -path $modObject.ManifestFilePath -Raw -Encoding UTF8).Replace($oldVersion, $newVersion)) | Set-Content -Path $modObject.ManifestFilePath
		((Get-Content -path $modObject.ModSyncFilePath -Raw -Encoding UTF8).Replace($oldVersion, $newVersion)) | Set-Content -Path $modObject.ModSyncFilePath
		if ($EndOfLife) {
			Set-ModUpdateFeatures -modObject $modObject -updateMessage "The original version of this mod has been updated, please use it instead. This version will remain, but unlisted and will not be updated further."
		} elseif ($Deprecated) {
			Set-ModUpdateFeatures -modObject $modObject -updateMessage "The features of this mod has now been included in the game. This mod will not be further updated but will stay up to support the previous versions of the game."
		} elseif ($Abandoned) {
			Set-ModUpdateFeatures -modObject $modObject -updateMessage "This mod will not be further updated."
		} elseif ($ReRelease) {
			Set-ModUpdateFeatures -modObject $modObject -updateMessage "This mod has been re-released for the new version of the game. This version will remain but will not be updated further."
		} elseif ($ReplacedBy) {
			$modInfo = Get-ModInfo -steamIds $ReplacedBy -expandAuthor
			$replacedByName = $modInfo.Name
			$replacedByAuthor = $modInfo.Author
			$replacedByLink = "[url=https://steamcommunity.com/sharedfiles/filedetails/?id=$ReplacedBy]$replacedByName[/url] by $replacedByAuthor"
			Set-ModUpdateFeatures -modObject $modObject -updateMessage "This mod will not be further updated, please use $replacedByName by $replacedByAuthor instead."
		} elseif (-not $ChangeNote) {
			Set-ModUpdateFeatures -modObject $modObject -Force:$Force
		}
	} else {
		ReadHost "Repository could not be found, create $($modObject.NameClean)?"
		New-GitRepository -repoName $modObject.NameClean
		Get-LatestGitVersion
		$message = "First publish"
		$newVersion = $version.ToString()
	}

	if ($extraCommitInfo) {
		$message += "`r`n$extraCommitInfo"
	}

	$version = [version]$newVersion
	Set-ModChangeNote -modObject $modObject -changenote "$version - $message" -Force:$Force

	$modObject = Get-Mod -originalModObject $modObject
	if (-not $Replacement) {
		if (-not $modObject.Published) {
			$firstPublish = $true
			if ($modObject.Continued) {
				Update-ModDescriptionFromPreviousMod -noConfirmation -localSearch -modObject $modObject -Force:$Force
				$modObject = Get-Mod -originalModObject $modObject
			}
			Update-ModUsageButtons -modObject $modObject -silent
			$modObject = Get-Mod -originalModObject $modObject
		} else {
			if (-not $ReRelease) {
				Sync-ModDescriptionFromSteam -modObject $modObject -Force:$Force
			}
			$modObject = Get-Mod -originalModObject $modObject
			if (-not $skipInteraction) {
				Update-ModMetadata -modObject $modObject -silent:$silent
			}
		}
	}
	$modObject = Get-Mod -originalModObject $modObject
	if ($modObject.Published -or $Replacement) {
		$description = $modObject.Description
		$indexOfIt = $description.IndexOf("[url=https://steamcommunity.com/sharedfiles/filedetails/changelog/")
		if ($indexOfIt -ne -1) {
			$description = $description.SubString(0, $indexOfIt)
		}
		$description = $description.Trim()

		if ($modObject.Continued -and -not $description.Contains("ReportingIssues.png")) {
			$description += $faqText
		}

		if (-not $modObject.Continued -and -not $description.Contains("Self-ReportingIssues.png")) {
			$description += $faqTextPrivate
		}
		$versionLogo = ""
		if ($modObject.PublishedId) {
			if ($modObject.Continued) {
				$logo = "https://img.shields.io/github/v/release/emipa606/$($modObject.NameClean)?label=latest%20version&style=plastic&color=9f1111&labelColor=black"
			} else {
				$logo = "https://img.shields.io/github/v/release/emipa606/$($modObject.NameClean)?label=latest%20version&style=plastic&labelColor=0070cd&color=white"
			}

			$versionLogo = "`n`n[url=https://steamcommunity.com/sharedfiles/filedetails/changelog/$($modObject.PublishedId)][img]$logo[/img][/url]"
		}
		$tags = ""
		if ($modObject.MetadataFileJson.SearchTags) {
			$tags = "| tags: " + ($modObject.MetadataFileJson.SearchTags -join ", ")
		}

		$modObject.AboutFileXml.ModMetaData.description = "$description $versionLogo $tags"
	}

	if ($modObject.MetadataFileJson.FundingSet) {
		$githubPath = "$($modObject.ModFolderPath)\.github"
		$fundingPath = "$githubPath\FUNDING.yml"
		if ($fundingFile -and (Test-Path $fundingFile) -and -not (Test-Path $fundingPath)) {
			if (-not (Test-Path $githubPath)) {
				New-Item -Path $githubPath -ItemType Directory -Force | Out-Null
			}
			Copy-Item -Path $fundingFile $fundingPath -Force
		}
	}

	if (-not $modObject.ModIconPath) {
		$modObject.ModIconPath = "$($modObject.ModFolderPath)\About\ModIcon.png"
		$modIcon = "E:\ModPublishing\Self-ModIcon.png"
		if ($modObject.Continued) {
			$modIcon = "E:\ModPublishing\ModIcon.png"
		}
		Copy-Item $modIcon $modObject.ModIconPath -Force -Confirm:$false
		WriteMessage -success "Added mod-icon to About-folder"
	} else {
		$modIcon = "E:\ModPublishing\Self-ModIcon.png"
		if ($modObject.Continued) {
			$modIcon = "E:\ModPublishing\ModIcon.png"
		}
		if (-not (Get-ImageSimilarity -original $modIcon -compare $modObject.ModIconPath)) {
			Copy-Item $modIcon $modObject.ModIconPath -Force -Confirm:$false
			WriteMessage -success "Fixed wrong modicon in the About-folder"
		}
	}

	if ($modObject.ModIconPath.StartsWith("$($modObject.ModFolderPath)\Textures")) {
		WriteMessage -progress "Moving modicon back from Textures to About-folder"
		Move-Item $modObject.ModIconPath "$($modObject.ModFolderPath)\About\ModIcon.png" -Confirm:$false -Force
		$modObject.ModIconPath = "$($modObject.ModFolderPath)\About\ModIcon.png"

		if (-not (Get-ChildItem "$($modObject.ModFolderPath)\Textures" -Recurse -File)) {
			WriteMessage -progress "Removing now empty Textures-folder"
			Remove-Item "$($modObject.ModFolderPath)\Textures" -Recurse -Force -Confirm:$false
		}

		if ($modObject.aboutFileXml.ModMetaData.modIconPath) {
			WriteMessage -progress "Removing modIconPath from about-file"
			$modObject.aboutFileXml.ModMetaData.RemoveChild($modObject.aboutFileXml.ModMetaData.modIconPath) | Out-Null
		}

		WriteMessage -success "Reverted mod-icon from Textures to About-folder"
	}

	WriteMessage -progress "Removing any empty folders in $($modObject.Name)"
	$allFolders = Get-ChildItem -Path $modObject.ModFolderPath -Directory -Recurse | Sort-Object { $_.FullName.Length } -Descending
	$removedFolders = 0
	foreach ($folder in $allFolders) {
		if (-not (Get-ChildItem -Path $folder.FullName -Recurse | Where-Object { -not $_.PSIsContainer })) {
			Remove-Item -Path $folder.FullName -Force -Recurse
			WriteMessage -progress "Removed empty folder: $($folder.FullName)"
			$removedFolders++
		}
	}
	if ($removedFolders -ne 0) {
		WriteMessage -success "Removed $removedFolders empty folders for $($modObject.Name)"
	}

	if (-not $modObject.AboutFileXml.ModMetaData.modVersion) {
		$newNode = $modObject.AboutFileXml.CreateElement("modVersion")
		$newNode.SetAttribute("IgnoreIfNoMatchingField", "True");
		$newNode.InnerText = "$newVersion"
		$modObject.AboutFileXml.ModMetaData.AppendChild($newNode) | Out-Null
	} else {
		$modObject.AboutFileXml.ModMetaData.modVersion.'#text' = $newVersion
	}

	Add-VersionTagOnImage -modObject $modObject -version $modObject.HighestSupportedVersion
	$modName = $modObject.NameClean
	if ($EndOfLife) {
		$modObject.AboutFileXml.ModMetaData.description = $modObject.AboutFileXml.ModMetaData.description.Replace("logos/Notice.png", "logos/Removed.png")
		if ($modObject.OriginalPublishedId) {
			Remove-ModReplacement -steamId $modObject.OriginalPublishedId -reverse
		}
		$modObject.AboutFileXml.ModMetaData.name = "[Abandoned] $($modObject.AboutFileXml.ModMetaData.name)"
	}
	if ($Deprecated) {
		$modObject.AboutFileXml.ModMetaData.description = $modObject.AboutFileXml.ModMetaData.description.Replace("logos/Notice.png", "logos/Deprication.png")
		$modObject.AboutFileXml.ModMetaData.name = "[Deprecated] $($modObject.AboutFileXml.ModMetaData.name)"
	}
	if ($Abandoned -or $ReplacedBy) {
		if ($Abandoned) {
			$modObject.AboutFileXml.ModMetaData.name = "[Abandoned] $($modObject.AboutFileXml.ModMetaData.name)"
		} else {
			$modObject.AboutFileXml.ModMetaData.name = "[Deprecated] $($modObject.AboutFileXml.ModMetaData.name)"
		}
		$modObject.AboutFileXml.ModMetaData.description = $modObject.AboutFileXml.ModMetaData.description.Replace("logos/Notice.png", "logos/Abandoned.png")
		if ($ReplacedBy) {
			logos
			$modObject.AboutFileXml.ModMetaData.description = $modObject.AboutFileXml.ModMetaData.description.Replace("logos/Abandoned.png[/img]", "logos/Abandoned.png[/img]`n`nThis mod has been replaced by $replacedByLink")
			New-ModReplacement -localName $modObject.Name -replacementSteamId $ReplacedBy -silent
		}
	}

	$modObject.AboutFileXml.ModMetaData.description = $modObject.AboutFileXml.ModMetaData.description.Trim()
	$modObject.AboutFileXml.Save($modObject.AboutFilePath)
	$modObject.Description = $modObject.AboutFileXml.ModMetaData.description
	if ($modObject.Published) {
		Sync-ModDescriptionToSteam -modObject $modObject -Force:$Force
		$modObject = Get-Mod -originalModObject $modObject
		WriteMessage -message "Updated the description" -success
	}

	# Copy replace modfiles
	if (-not $modObject.ReadMePath) {
		$modObject.ReadMePath = "$($modObject.ModFolderPath)\README.md"
	}
	"# [$($modObject.DisplayName)]($($modObject.ModUrl))`n`r" > $modObject.ReadMePath
	(Convert-BBCodeToGithub -textToConvert $modObject.Description) >> $modObject.ReadMePath
	Set-SafeGitFolder

	# Reapply gitignore-file if necessary
	if ($reapplyGitignore) {
		git rm -r --cached .
	}

	git add .
	git commit -S -m $message
	git push origin

	if (-not $ReRelease) {
		$tagMessage = $message
		if ($tagMessage.Length -gt 256) {
			$tagMessage = $tagMessage.Substring(0, 252) + "..."
		}
		git tag -s -a $newVersion -m $tagMessage
		git push --tags

		$releaseData = @{
			tag_name = $newVersion;
			name     = $tagMessage;
		}
		$releaseParams = @{
			Uri         = "https://api.github.com/repos/$($settings.github_username)/$($modObject.NameClean)/releases";
			Method      = 'POST';
			Headers     = @{
				Authorization = 'Basic ' + [Convert]::ToBase64String(
					[Text.Encoding]::ASCII.GetBytes($gitApiToken + ":x-oauth-basic"));
			}
			ContentType = 'application/json';
			Body        = (ConvertTo-Json $releaseData -Compress)
		}
		$createdRelease = Invoke-RestMethod @releaseParams

		WriteMessage -progress "Creating zip-file"
		Get-ZipFile -modObject $modObject -filename "$($modObject.NameClean)_$newVersion.zip"
		$zipFile = Get-Item "$($modObject.ModFolderPath)\$($modObject.NameClean)_$newVersion.zip"
		$fileName = $zipFile.Name
		$uploadParams = @{
			Uri     = "https://uploads.github.com/repos/$($settings.github_username)/$($modObject.NameClean)/releases/$($createdRelease.id)/assets?name=$fileName&label=$fileName";
			Method  = 'POST';
			Headers = @{
				Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($gitApiToken + ":x-oauth-basic"));
			}
		}

		WriteMessage -progress "Uploading zip-file"
		$uploadedFile = Invoke-RestMethod @uploadParams -InFile $zipFile.FullName -ContentType "application/zip"
		WriteMessage -progress "Upload status: $($uploadedFile.state)"
		Remove-Item $zipFile.FullName -Force
	}

	if ($EndOfLife -or $Deprecated -or $Abandoned -or $ReplacedBy) {
		Set-GitRepositoryToArchived -repoName $modObject.NameClean
	} else {
		Set-DefaultGithubRepoValues -modObject $modObject
	}
	if ($GithubOnly) {
		WriteMessage -warning "Published $($modObject.Name) to github only!"
		SetTerminalProgress
		return
	}

	Start-SteamPublish -modObject $modObject -Force:$Force -NoConfirm:$Replacement
	$modObject = Get-Mod -originalModObject $modObject

	if (-not $SkipNotifications -and $modObject.Published) {
		if ($firstPublish -and -not $Replacement) {
			Push-UpdateNotification -modObject $modObject
			$modObject = Get-Mod -originalModObject $modObject
			Get-ModPage
			if ($modObject.Continued -and $modObject.Description -match "https://steamcommunity.com/sharedfiles/filedetails") {
				$previousModId = (($modObject.Description -split "https://steamcommunity.com/sharedfiles/filedetails/\?id=")[1] -split "[^0-9]")[0]
				$trelloCard = Find-TrelloCardByCustomField -text "https://steamcommunity.com/sharedfiles/filedetails/?id=$previousModId" -fieldId $trelloLinkId
				if ($trelloCard) {
					Move-TrelloCardToDone -cardId $trelloCard.id
				}
				$link = Get-ModPage -getLink
				Push-ModComment -modId $previousModId -Comment "Made an update of this:`n$link`nHope it helps anyone!"

				New-ModReplacement -steamId $previousModId -replacementLocalName $modObject.Name -silent
				$originalIds = ReadHost "Insert one or more extra ids (separated by ,) for $modName or leave empty if no more replacements"
				if ($originalIds) {
					if ($originalIds -match ",") {
						foreach ($originalId in $originalIds.Split(",")) {
							New-ModReplacement -steamId $originalId.Trim() -replacementLocalName $modObject.Name -silent
						}
					} else {
						New-ModReplacement -steamId $originalIds -replacementLocalName $modObject.Name -silent
					}
				}
			}
		} else {
			if (-not $Silent) {
				if ($Auto) {
					Close-TrelloCardsForMod -modObject $modObject -justMajorVersion
					if (-not $Replacement) {
						Push-ModComment -modObject $modObject -Comment "Mod updated for $(Get-CurrentRimworldVersion)"
					}
				} else {
					Close-TrelloCardsForMod -modObject $modObject -closeAll:($skipInteraction)
				}
			}
		}

		if ($ExtraInfo) {
			$message = "$message`r`n$ExtraInfo"
		}
		Push-UpdateNotification -modObject $modObject -Changenote "$version - $message"

		if ($Comment) {
			Push-ModComment -modObject $modObject -Comment $Comment
		}
	}
	SetTerminalProgress
	if ($EndOfLife) {
		WriteMessage -success "Repository set to archived, mod set to unlisted. Moving local mod-folder to Archived"
		Push-UpdateNotification -modObject $modObject -Changenote "Original version updated, mod set to unlisted. Will not be further updated" -EndOfLife
		Set-Location $localModFolder
		Move-Item -Path $modObject.ModFolderPath -Destination "$stagingDirectory\..\Archive\" -Force -Confirm:$false
		Update-ModInfoToDatabase -modObject $modObject -archive
		WriteMessage -success "Archived $($modObject.Name)"
		return
	}
	if ($Deprecated) {
		WriteMessage -success "Repository set to archived. Moving local mod-folder to Archived"
		Push-UpdateNotification -modObject $modObject -Changenote "The mod has now been included in the game. Will not be further updated" -EndOfLife
		Set-Location $localModFolder
		Move-Item -Path $modObject.ModFolderPath -Destination "$stagingDirectory\..\Archive\" -Force -Confirm:$false
		Update-ModInfoToDatabase -modObject $modObject -archive
		WriteMessage -success "Archived $($modObject.Name)"
		return
	}
	if ($Abandoned -or $ReplacedBy) {
		WriteMessage -success "Repository set to archived. Moving local mod-folder to Archived"
		if ($ReplacedBy) {
			Push-UpdateNotification -modObject $modObject -Changenote "Mod will not be further updated, please use $replacedByName instead: https://steamcommunity.com/sharedfiles/filedetails/?id=$ReplacedBy" -EndOfLife
		} else {
			Push-UpdateNotification -modObject $modObject -Changenote "Mod will not be further updated" -EndOfLife
		}
		Set-Location $localModFolder
		Move-Item -Path $modObject.ModFolderPath -Destination "$stagingDirectory\..\Archive\" -Force -Confirm:$false
		Update-ModInfoToDatabase -modObject $modObject -archive
		WriteMessage -success "Archived $($modObject.Name)"
		return
	}
	WriteMessage -progress "Running Git Cleanup"
	git gc --auto
	if ($ReRelease) {
		Push-ModComment -modObject $modObject -Comment "Mod re-relased for $(Get-CurrentRimworldVersion), see info in the description"
	} else {
		Publish-ModToRimWorldBase -modObject $modObject
		Update-ModInfoToDatabase -modObject $modObject
	}
	WriteMessage -success "Published $($modObject.Name) - $($modObject.ModUrl)"
}

# Steam-publishing
function Start-SteamPublish {
	param(
		$modObject,
		[switch]$Force,
		[switch]$Confirm,
		[switch]$NoConfirm
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}
	if (-not $modObject.ModFolderPath) {
		WriteMessage -failure "$($modObject.Name) does not have a folder defined"
		return
	}
	if (-not $Force -and -not $modObject.Mine) {
		WriteMessage -failure "$($modObject.Name) is not mine, aborting update"
		return
	}
	$copyPublishedFileId = -not $modObject.Published
	$stagingDirectory = $settings.mod_staging_folder
	$previewDirectory = "$($settings.mod_staging_folder)\..\PreviewStaging"
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse -ProgressAction SilentlyContinue
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse -ProgressAction SilentlyContinue
	Get-ChildItem -Path $previewDirectory -Recurse | Remove-Item -force -recurse -ProgressAction SilentlyContinue
	Get-ChildItem -Path $previewDirectory -Recurse | Remove-Item -force -recurse -ProgressAction SilentlyContinue

	WriteMessage -progress "Copying mod-files to publish-dir"
	$exclusions = @()

	if ($modObject.ModPublisherPath) {
		foreach ($exclusion in ([xml](Get-Content $modObject.ModPublisherPath -Raw -Encoding UTF8)).Configuration.Excluded.exclude) {
			$exclusions += $exclusion.Replace("$($modObject.ModFolderPath)\", "")
		}
		$exclusions += $($modObject.ModPublisherPath).Replace("$($modObject.ModFolderPath)\", "")
	}
	Copy-Item -Path "$($modObject.ModFolderPath)\*" -Destination $stagingDirectory -Recurse -Exclude $exclusions
	if ($copyPublishedFileId -or $Force) {
		WriteMessage -progress "Copying previewfiles to preview-dir"
		$inclusions = @("*.png", "*.jpg", "*.gif")
		Copy-Item -Path "$($modObject.ModFolderPath)\Source\*" -Destination $previewDirectory -Include $inclusions
	}
	if (Test-Path "$($modObject.ModFolderPath)\Source\Preview.gif") {
		Copy-Item -Path "$($modObject.ModFolderPath)\Source\Preview.gif" -Destination $previewDirectory
	}

	WriteMessage -progress "Starting steam-publish"
	$publishToolPath = "$($settings.script_root)\SteamUpdateTool\Compiled\RimworldModReleaseTool.exe"
	$arguments = @($stagingDirectory, $previewDirectory)
	if ($Confirm) {
		$arguments += "True"
	} else {
		if ($NoConfirm) {
			$arguments += "False"
		}
	}
	Start-Process -FilePath $publishToolPath -ArgumentList $arguments -Wait -NoNewWindow
	if ($copyPublishedFileId -and (Test-Path "$stagingDirectory\About\PublishedFileId.txt")) {
		$modObject.Published = $true
		$modObject.PublishedIdFilePath = "$($modObject.ModFolderPath)\About\PublishedFileId.txt"
		Copy-Item -Path "$stagingDirectory\About\PublishedFileId.txt" -Destination $modObject.PublishedIdFilePath -Force
		$modObject.PublishedId = Get-Content $modObject.PublishedIdFilePath -Raw
		$modObject.ModUrl = "https://steamcommunity.com/sharedfiles/filedetails/?id=$($modObject.PublishedId)"
	}
	return
}

# Simple update-notification for Discord
function Push-UpdateNotification {
	param(
		$modObject,
		[switch]$Test,
		[string]$Changenote,
		[switch]$EndOfLife
	)
	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not $modObject.AboutFilePath) {
		return
	}

	if ($EndOfLife) {
		$discordHookUrl = $discordRemoveHookUrl
		$repoUrl = Get-ModRepository -getLink
		$content = (Get-Content $discordRemoveMessage -Raw -Encoding UTF8).Replace("[modname]", $($modObject.DisplayName)).Replace("[repourl]", $repoUrl).Replace("[endmessage]", $Changenote)
	} else {
		if ($Changenote.Length -gt 0) {
			$discordHookUrl = $discordUpdateHookUrl
			$content = (Get-Content $discordUpdateMessage -Raw -Encoding UTF8).Replace("[modname]", $($modObject.DisplayName)).Replace("[modurl]", $modObject.ModUrl).Replace("[changenote]", $Changenote)
		} else {
			$discordHookUrl = $discordPublishHookUrl
			$content = (Get-Content $discordPublishMessage -Raw -Encoding UTF8).Replace("[modname]", $($modObject.DisplayName)).Replace("[modurl]", $modObject.ModUrl)
		}
	}

	if ($Test) {
		$discordHookUrl = $discordTestHookUrl
		WriteMessage -progress "Posting the message to test-channel"
	}

	$payload = [PSCustomObject]@{
		content  = $content
		username = "Update Bot"
	}
	try {
		Invoke-RestMethod -Uri $discordHookUrl -Method Post -Headers @{ "Content-Type" = "application/json" } -Body ($payload | ConvertTo-Json) | Out-Null
		WriteMessage -success "Message posted to Discord"
	} catch {
		WriteMessage -failure "Failed to post message to Discord"
	}
}

function Publish-ModToRimWorldBase {
	[CmdletBinding()]
	param(
		$modObject
	)

	if (-not $rimworldBaseApiKey) {
		WriteMessage -failure "No RimWorldBase API key defined, cannot publish"
		return
	}

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($rimWorldBaseApiUser):$($rimworldBaseApiKey)"))
	$updateHeader = @{
		"Authorization" = "Basic $base64AuthInfo"
		"Content-Type"  = "application/json"
	}
	$new = $false
	if (-not $modObject.MetadataFileJson.RimWorldBaseId) {
		$new = $true
		WriteMessage "$($modObject.Name) is not listed on RimWorldBase, creating a new entry"
		$modDescription = $modObject.DescriptionClean.Trim()
		$modDescription = $modDescription.Replace("[b]", "<strong>").Replace("[/b]", "</strong>")
		$modDescription = $modDescription.Replace("[i]", "<em>").Replace("[/i]", "</em>")
		$modDescription = $modDescription.Replace("[u]", "<u>").Replace("[/u]", "</u>")
		$modDescription = $modDescription.Replace("[img]", "<img src=`"").Replace("[/img]", "`" />")
		$modDescription = $modDescription.Replace("[url=", "<a href=`"").Replace("]", "`">").Replace("[/url]", "</a>")
		$modDescription = $modDescription.Replace("[list]", "<ul>").Replace("[/list]", "</ul>")
		$modDescription = $modDescription.Replace("[*]", "<li>").Replace("[/li]", "</li>")
		$modDescription = $modDescription.Replace("&#39;", "'").Replace("`r`n", "<br />").Replace("`n", "<br />")

		# Check if there are any preview images on steam and add them to the description
		$failed = $false
		try {
			$steamPage = Invoke-WebRequest -Uri $modObject.ModUrl -UseBasicParsing
		} catch {
			WriteMessage -failure "Failed to fetch steam page, waiting 10 seconds and trying again"
			$failed = $true
		}

		# We just updated the steam-page so it may not be available right away, check for the text of Steam Community :: Error
		if ($failed -or $steamPage.Content -match "Steam Community :: Error") {
			for ($i = 0; $i -lt 5; $i++) {
				WriteMessage -progress "Steam page not available yet, waiting 10 seconds and trying again"
				Start-Sleep -Seconds 10
				$failed = $false
				try {
					$steamPage = Invoke-WebRequest -Uri $modObject.ModUrl -UseBasicParsing
				} catch {
					WriteMessage -failure "Failed to fetch steam page, waiting 10 seconds and trying again"
					$failed = $true
				}
				if (-not $failed -and $steamPage.Content -notmatch "Steam Community :: Error") {
					break
				}
			}
		}
		if ($failed -or $steamPage.Content -match "Steam Community :: Error") {
			WriteMessage -failure "Steam page still not available, skipping adding preview images"
		} else {
			$html = $steamPage.Content
			$regex = '<img\s+src="([^"]+steamusercontent[^"]+)"'
			$imageUrls = [regex]::Matches($html, $regex) | ForEach-Object {
				($_.Groups[1].Value -replace '&amp;', '&').Split('?')[0]
			}

			if ($imageUrls.Count -gt 0) {
				WriteMessage -progress "Adding $($imageUrls.Count) preview images from steam to the description"
				$modDescription += "<br />" + ($imageUrls | ForEach-Object { "<img src=`"$($_)?imw=800&ima=fit&impolicy=Letterbox`" />" }) -join "<br />"
			}
		}

		WriteMessage -progress "Creating new mod entry on RimWorldBase"
		$body = @{
			title   = "$($modObject.DisplayName) Mod"
			status  = "draft"
			content = $modDescription
		} | ConvertTo-Json

		$postUrl = $rimWorldBaseApiUrl.Replace("acf/v3/posts/", "wp/v2/posts")
		$response = Invoke-RestMethod -Uri $postUrl -Method Post -Headers $updateHeader -Body $body
		$rimworldBaseId = $response.id
		$postUrl = "$postUrl/$rimworldBaseId"
		$modObject.MetadataFileJson = $modObject.MetadataFileJson | Add-Member -MemberType NoteProperty -Name RimWorldBaseId -Value $rimworldBaseId -Force -PassThru
		$modObject.MetadataFileJson | ConvertTo-Json -Depth 5 | Set-Content -Path $modObject.MetadataFilePath -Encoding UTF8

		WriteMessage -progress "Uploading preview image"
		$imageBytes = [System.IO.File]::ReadAllBytes($modObject.PreviewFilePath)
		$mediaUrl = $rimWorldBaseApiUrl.Replace("acf/v3/posts/", "wp/v2/media")
		$mediaHeader = @{
			"Authorization"       = "Basic $base64AuthInfo"
			"Content-Disposition" = "attachment; filename=`"$($modObject.NameClean).png`""
			"Content-Type"        = "image/png"
		}
		$response = Invoke-RestMethod -Uri $mediaUrl -Method Post -Headers $mediaHeader -Body $imageBytes
		$mediaId = $response.id
		$body = @{ featured_media = $mediaId } | ConvertTo-Json
		WriteMessage -progress "Setting preview image as featured media"
		$response = Invoke-RestMethod -Uri $postUrl -Method Post -Headers $updateHeader -Body $body
	}

	# Fetch all existing field data
	$rimworldBaseId = $modObject.MetadataFileJson.RimWorldBaseId
	$url = "$($rimWorldBaseApiUrl)$rimworldBaseId"
	$response = Invoke-RestMethod -Uri $url -Method Get -Headers @{
		"Authorization" = "Basic $base64AuthInfo"
	}
	$fields = $response.acf
	$anythingChanged = $false

	# Parse all fields and update if necessary
	if (-not $fields.is_a_downloadable) {
		WriteMessage -progress "Setting mod to downloadable"
		$body = @{ fields = @{ is_a_downloadable = $true } } | ConvertTo-Json -Depth 5
		$response = Invoke-RestMethod -Uri $url -Method Post -Headers $updateHeader -Body $body
		$fields = $response.acf
		$anythingChanged = $true
	}

	if (-not $fields.is_content_author) {
		WriteMessage -progress "Setting content author"
		$body = @{ fields = @{ is_content_author = $true } } | ConvertTo-Json -Depth 5
		$response = Invoke-RestMethod -Uri $url -Method Post -Headers $updateHeader -Body $body
		$fields = $response.acf
		$anythingChanged = $true
	}

	if (-not $fields.is_updated) {
		WriteMessage -progress "Setting is_updated to true"
		$body = @{ fields = @{ is_updated = $true } } | ConvertTo-Json -Depth 5
		$response = Invoke-RestMethod -Uri $url -Method Post -Headers $updateHeader -Body $body
		$fields = $response.acf
		$anythingChanged = $true
	}

	$wantsDonations = $(-not $modObject.Continued)
	if ($fields.wants_donations -ne $wantsDonations) {
		WriteMessage -progress "Setting wants_donations to $wantsDonations"
		$body = @{ fields = @{ wants_donations = $wantsDonations } } | ConvertTo-Json -Depth 5
		$response = Invoke-RestMethod -Uri $url -Method Post -Headers $updateHeader -Body $body
		$fields = $response.acf
		$anythingChanged = $true
	}

	if ($wantsDonations -and $fields.kofi_url_list.kofi_url -ne $kofiUrl) {
		WriteMessage -progress "Setting kofi_url to $kofiUrl"
		$body = @{ fields = @{ kofi_url_list = @( @{ kofi_url = $kofiUrl } ) } } | ConvertTo-Json -Depth 5
		$response = Invoke-RestMethod -Uri $url -Method Post -Headers $updateHeader -Body $body
		$fields = $response.acf
		$anythingChanged = $true
	}

	if ($fields.steam_download -ne $modObject.ModUrl) {
		WriteMessage -progress "Setting steam_download to $($modObject.ModUrl)"
		$body = @{ fields = @{ steam_download = $modObject.ModUrl } } | ConvertTo-Json -Depth 5
		$response = Invoke-RestMethod -Uri $url -Method Post -Headers $updateHeader -Body $body
		$fields = $response.acf
		$anythingChanged = $true
	}

	$directDownloadUrl = "$($modObject.Repository)/releases/download/$($modObject.Version)/$($modObject.NameClean)_$($modObject.Version).zip"
	if ($fields.direct_download -ne $directDownloadUrl) {
		WriteMessage -progress "Setting direct_download to $directDownloadUrl"
		$body = @{ fields = @{ direct_download = $directDownloadUrl } } | ConvertTo-Json -Depth 5
		$response = Invoke-RestMethod -Uri $url -Method Post -Headers $updateHeader -Body $body
		$fields = $response.acf
		$anythingChanged = $true
	}

	$requiresNewGame = $modObject.MetadataFileJson.CanAdd -eq "2"
	if ($fields.requires_new_game -ne $requiresNewGame) {
		WriteMessage -progress "Setting requires_new_game to $requiresNewGame"
		$body = @{ fields = @{ requires_new_game = $requiresNewGame } } | ConvertTo-Json -Depth 5
		$response = Invoke-RestMethod -Uri $url -Method Post -Headers $updateHeader -Body $body
		$fields = $response.acf
		$anythingChanged = $true
	}

	$hasRequirements = $modObject.AboutFileXml.ModMetaData.modDependencies?.Length -gt 0 -or $modObject.AboutFileXml.ModMetaData.modDependenciesByVersion?.Length -gt 0
	if ($fields.requires_libraries -ne $hasRequirements) {
		WriteMessage -progress "Setting requires_libraries to $hasRequirements"
		$body = @{ fields = @{ requires_libraries = $hasRequirements } } | ConvertTo-Json -Depth 5
		$response = Invoke-RestMethod -Uri $url -Method Post -Headers $updateHeader -Body $body
		$fields = $response.acf
		$anythingChanged = $true
	}

	if ($hasRequirements) {
		$gameVersion = Get-CurrentRimworldVersion
		$requiresHarmony = $modObject.AboutFileXml.ModMetaData.modDependencies.li.packageId?.Contains("brrainz.harmony") -or $modObject.AboutFileXml.ModMetaData.modDependenciesByVersion."v$gameVersion".li.packageId?.Contains("brrainz.harmony")
		if ($requiresHarmony -and (-not $fields.libraries_list -or $fields.libraries_list -notcontains 8517)) {
			WriteMessage -progress "Adding harmony to libraries_list"
			if (-not $fields.libraries_list) {
				$fields | Add-Member -MemberType NoteProperty -Name libraries_list -Value @()
			}
			$fields.libraries_list += 8517
			$somethingChanged = $true
		}
		$requiresVanillaExpanded = $modObject.AboutFileXml.ModMetaData.modDependencies.li.packageId?.Contains("OskarPotocki.VanillaFactionsExpanded.Core") -or $modObject.AboutFileXml.ModMetaData.modDependenciesByVersion."v$gameVersion".li.packageId?.Contains("OskarPotocki.VanillaFactionsExpanded.Core")
		if ($requiresVanillaExpanded -and (-not $fields.libraries_list -or $fields.libraries_list -notcontains 9172)) {
			WriteMessage -progress "Adding vanilla expanded to libraries_list"
			if (-not $fields.libraries_list) {
				$fields | Add-Member -MemberType NoteProperty -Name libraries_list -Value @()
			}
			$fields.libraries_list += 9172
			$somethingChanged = $true
		}
		if ($somethingChanged) {
			$body = @{ fields = @{ libraries_list = $fields.libraries_list } } | ConvertTo-Json -Depth 5
			$response = Invoke-RestMethod -Uri $url -Method Post -Headers $updateHeader -Body $body
			$fields = $response.acf
			$anythingChanged = $true
		}

		# Check for DLCs
		$requiredDLCs = @()
		foreach ($packageId in $modObject.AboutFileXml.ModMetaData.modDependencies.li.packageId) {
			if ($packageId.StartsWith("Ludeon.Rimworld.")) {
				$requiredDLCs += $packageId.Replace("Ludeon.Rimworld.","")
			}
		}
		if ($fields.required_dlc -ne $requiredDLCs) {
			WriteMessage -progress "Setting required_dlc to $requiredDLCs"
			if ($requiredDLCs.Count -eq 1) {
				$body = @{ fields = @{ required_dlc = @($requiredDLCs) } } | ConvertTo-Json -Depth 5
			} else {
				$body = @{ fields = @{ required_dlc = $requiredDLCs } } | ConvertTo-Json -Depth 5
			}
			$response = Invoke-RestMethod -Uri $url -Method Post -Headers $updateHeader -Body $body
			$fields = $response.acf
			$anythingChanged = $true
		}
	}

	$url = $url.Replace("acf", "wp").Replace("v3", "v2")
	$response = Invoke-RestMethod -Uri $url -Method Get -Headers @{
		"Authorization" = "Basic $base64AuthInfo"
	}

	if ($response.status -eq "draft") {
		WriteMessage -progress "Setting mod to pending"
		$body = @{ status = "pending" } | ConvertTo-Json -Depth 5
		$response = Invoke-RestMethod -Uri $url -Method Post -Headers $updateHeader -Body $body
	}

	if (-not $anythingChanged) {
		WriteMessage -progress "No changes necessary"
		return
	}
	$now = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss")
	$body = @{ date = $now } | ConvertTo-Json -Depth 5
	$response = Invoke-RestMethod -Uri $url -Method Post -Headers $updateHeader -Body $body

	if ($new) {
		WriteMessage -success "Created new entry for $($modObject.Name) on RimWorldBase: $($response.link)"
	} else {
		WriteMessage -progress "Updated $($modObject.Name) on RimWorldBase: $($response.link)"
	}
}

#endregion

#region Image functions

# Adds an image on an image
function Add-ImageOnImage {
	param(
		$baseImagePath,
		$overlayImagePath,
		$outputPath
	)

	$previewImage = New-Object -ComObject Wia.ImageFile
	$previewImage.LoadFile($baseImagePath)
	$baseImage = $baseImagePath

	if ($previewImage.Width -lt 400 -or $previewImage.Height -lt 400) {
		WriteMessage -progress "Original preview too small, adding padding"
		$newTempPath = "$($env:TEMP)\tempfile.png"
		if (Test-Path $newTempPath) {
			Remove-Item $newTempPath -Force
		}

		$newWidth = [math]::Max($previewImage.Width, 400)
		$newHeight = [math]::Max($previewImage.Height, 400)
		& magick "$baseImagePath" -background transparent -gravity center -extent "$($newWidth)x$($newHeight)" "$newTempPath"
		$baseImage = $newTempPath
	}

	$tagWidth = [math]::Round($previewImage.Width / 6, 3)
	$tagHeight = [math]::Round(($tagWidth / $previewImage.Width) * $previewImage.Height, 3)
	$tagMargin = [math]::Round($previewImage.Width / 50, 3)

	if (Test-Path $outputPath) {
		Remove-Item $outputPath -Force -Confirm:$false | Out-Null
	}
	& magick "$baseImage" "$overlayImagePath" -gravity NorthEast -geometry "$($tagWidth)x$($tagHeight)+$tagMargin+$tagMargin" -composite "$outputPath"
}

function Set-ImageSizeBelow {
	param (
		$imagePath,
		$sizeInKb,
		[switch]$removeOriginal
	)
	if (-not (Test-Path $imagePath)) {
		WriteMessage -failure "Cannot find image at $imagePath, exiting"
		return
	}
	if ((Get-Item $imagePath).Length -le $sizeInKb * 1kb) {
		return
	}
	$imageName = Split-Path -Leaf $imagePath
	$imageDir = Split-Path $imagePath
	Copy-Item $imagePath $env:TEMP -Force -Confirm:$false
	Copy-Item $imagePath "$env:TEMP\_$imageName" -Force -Confirm:$false
	$percent = 100
	while ((Get-Item "$env:TEMP\$imageName").Length -gt $sizeInKb * 1kb) {
		$percent--
		if ($percent -eq 0) {
			WriteMessage -warning "At 0 percent, cannot lower size any more"
			return
		}
		Set-ImageSizePercent -imagePath "$env:TEMP\_$imageName" -percent $percent -outName $imageName -overwrite -silent
	}
	if ($removeOriginal) {
		Remove-Item $imagePath -Force -Confirm:$false
	} else {
		Move-Item $imagePath "$imageDir\original_$imageName" -Confirm:$false
	}
	Move-Item "$env:TEMP\$imageName" $imagePath -Confirm:$false
}


function Set-ImageSizePercent {
	param(
		$imagePath,
		$percent,
		$outName,
		[switch]$overwrite,
		[switch]$silent
	)

	Add-Type -AssemblyName System.Drawing
	if (-not (Test-Path $imagePath)) {
		WriteMessage -failure "Cannot find image at $imagePath, exiting"
		return
	}
	if (-not $percent) {
		WriteMessage -failure "Must define a resize percent"
		return
	}
	$originalFile = Split-Path -Leaf $imagePath
	$outPath = $imagePath.Replace($originalFile, $outName)
	if (Test-Path $outPath) {
		if ($overwrite) {
			Remove-Item $outPath -Confirm:$false -Force | Out-Null
		} else {
			WriteMessage -failure "$outPath already exists, remove it first"
			return
		}
	}
	$img = [System.Drawing.Image]::FromFile((Get-Item $imagePath))
	[int32]$newWidth = $img.Width * ($percent / 100)
	[int32]$newHeight = $img.Height * ($percent / 100)
	$canvas = New-Object System.Drawing.Bitmap($newWidth, $newHeight)
	$graph = [System.Drawing.Graphics]::FromImage($canvas)
	$graph.DrawImage($img, 0, 0, $newWidth, $newHeight)
	$canvas.Save($outPath)
	$canvas.Dispose()
	$img.Dispose()
	if (-not $silent) {
		WriteMessage -success "Saved the resized image to $outPath"
	}
}


function Set-ImageMaxSize {
	param(
		$imagePath,
		$pixels,
		$outName,
		[switch]$overwrite,
		[switch]$silent
	)

	Add-Type -AssemblyName System.Drawing
	if (-not (Test-Path $imagePath)) {
		WriteMessage -failure "Cannot find image at $imagePath, exiting"
		return
	}
	$fullImagePath = (Get-Item $imagePath).FullName
	if (-not $pixels) {
		WriteMessage -failure "Must define a max size in pixels"
		return
	}
	$originalFile = Split-Path -Leaf $fullImagePath
	$outPath = $fullImagePath.Replace($originalFile, $outName)
	if ((Test-Path $outPath) -and -not $overwrite) {
		WriteMessage -failure "$outPath already exists, remove it first or use the overwrite parameter"
		return
	}
	$img = [System.Drawing.Image]::FromFile((Get-Item $imagePath))
	if ($img.Width -le $pixels -and $img.Height -le $pixels ) {
		WriteMessage -progress "Image already within $pixels length/height"
		if ($fullImagePath -ne $outPath) {
			Copy-Item $imagePath $outPath -Force
		}
		return
	}
	if ($img.Height -gt $img.Width) {
		[int32]$newHeight = $pixels
		[int32]$newWidth = $img.Width * ($pixels / $img.Height)
	} else {
		[int32]$newWidth = $pixels
		[int32]$newHeight = $img.Height * ($pixels / $img.Width)
	}

	if (-not $silent) {
		WriteMessage -progress "New size: $newWidth x $newHeight"
	}

	$canvas = New-Object System.Drawing.Bitmap($newWidth, $newHeight)
	$graph = [System.Drawing.Graphics]::FromImage($canvas)
	$graph.DrawImage($img, 0, 0, $newWidth, $newHeight)
	$img.Dispose()
	if ($fullImagePath -eq $outPath) {
		Remove-Item $outPath -Confirm:$false -Force | Out-Null
	}
	$canvas.Save($outPath)
	$canvas.Dispose()
	if (-not $silent) {
		WriteMessage -progress "Saved the resized image to $outPath"
	}
}

function Update-InfoBanner {
	param (
		$modObject,
		[switch] $force
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not $modObject.PreviewFilePath) {
		WriteMessage -failure "Found no preview image to create a banner from"
		return
	}

	$updatebannerPath = "$($modObject.ModFolderPath)\Textures\UpdateInfo\$($modObject.Name).png"
	$updatebannerTempPath = "$($modObject.ModFolderPath)\Textures\UpdateInfo\$($modObject.Name)_temp.png"
	if (-not $force -and (Test-Path $updatebannerPath)) {
		return
	}

	$updatebannerFolder = Split-Path $updatebannerPath
	if (-not (Test-Path $updatebannerFolder)) {
		New-Item -Path $updatebannerFolder -ItemType Directory -Force | Out-Null
	}

	Add-Type -AssemblyName System.Drawing

	Copy-Item $modObject.PreviewFilePath $updatebannerTempPath -Force
	Set-ImageMaxSize -imagePath $updatebannerTempPath -pixels 200 -outName (Split-Path $updatebannerTempPath -Leaf) -overwrite -silent
	$tempImageObject = [System.Drawing.Image]::FromFile($updatebannerTempPath)
	$height = $tempImageObject.Height
	$tempImageObject.Dispose()

	& magick "$updatebannerTempPath" -background transparent -gravity West -extent "$(500)x$($height)" "$updatebannerPath"
	Start-Sleep -Seconds 1
	Remove-Item $updatebannerTempPath -Force
	Move-Item $updatebannerPath $updatebannerTempPath -Force

	& magick -background transparent -gravity West -font RimWordFont -fill 'rgba(222,222,222,1)' -size "$(275)x$($height * 0.9)" caption:"$($modObject.DisplayName)" "$updatebannerTempPath" +swap -gravity East -composite "$updatebannerPath"
	Start-Sleep -Seconds 1
	Remove-Item $updatebannerTempPath -Force
}

function Get-ImageSimilarity {
	param(
		$original,
		$compare
	)

	if (-not (Test-Path $original)) {
		WriteMessage -failure "No image found at $original"
		return $false
	}

	if (-not (Test-Path $compare)) {
		WriteMessage -failure "No image found at $compare"
		return $false
	}

	$result = magick compare -metric MSE $original $compare "$env:TEMP\compare.png" 2>&1 | ForEach-Object ToString
	$resultDifference = $result.Split(" ")[0]

	return $resultDifference -lt 10
}

function New-AssetBundle {
	param(
		$modObject
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			WriteMessage -failure "No mod object provided, exiting"
			return
		}
	}

	$sourcePath = $modObject.AssetSourcePath
	$targetPath = $modObject.AssetBundlesPath
	$prefix = $modObject.ModId
	$assetFileName = $prefix.Replace(".", "_")

	if (-not (Test-Path $sourcePath)) {
		WriteMessage -failure "Cannot find $sourcePath, exiting"
		return
	}
	if (-not (Test-Path $targetPath)) {
		WriteMessage -failure "Cannot find $targetPath, exiting"
		return
	}
	if ($targetPath -eq $sourcePath) {
		WriteMessage -failure "Source and target path are the same, exiting"
		return
	}
	if ((Get-ChildItem $sourcePath -Recurse -File | Measure-Object -Sum Length).Sum -eq 0) {
		WriteMessage -failure "Source path is empty, exiting"
		return
	}

	$inputPath = "$($unityBundleProjectPath)\Assets\Data"
	WriteMessage -progress "Cleaning up $inputPath"
	Remove-Item -Path $inputPath -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue -ProgressAction SilentlyContinue
	New-Item -Path $inputPath -ItemType Directory -Force | Out-Null

	$outputPath = "$($unityBundleProjectPath)\Assets\AssetBundles"
	WriteMessage -progress "Cleaning up $outputPath"
	Remove-Item -Path $outputPath -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue -ProgressAction SilentlyContinue
	New-Item -Path $outputPath -ItemType Directory -Force | Out-Null

	$inputPath = "$($unityBundleProjectPath)\Assets\Data\$prefix"
	WriteMessage -progress "Creating $inputPath"
	New-Item -Path $inputPath -ItemType Directory -Force | Out-Null

	WriteMessage -progress "Copying files to $inputPath"
	Copy-Item -Path "$sourcePath\*" -Destination $inputPath -Recurse -Force -Confirm:$false

	WriteMessage "Generating AssetBundle for $($targetPath)"
	Start-Process -FilePath $unityPath -ArgumentList "-batchmode","-quit","-projectPath ""$unityBundleProjectPath""","-executeMethod ModAssetBundleBuilder.BuildBundles","--assetBundleName=$assetFileName" -NoNewWindow -Wait

	if (-not (Test-Path "$($unityBundleProjectPath)\Assets\AssetBundles\$assetFileName")) {
		WriteMessage -failure "Failed to create AssetBundle, exiting"
		return
	}

	WriteMessage -progress "Cleaning up $targetPath"
	Remove-Item -Path $targetPath -Recurse -Force -Confirm:$false -ErrorAction SilentlyContinue -ProgressAction SilentlyContinue
	New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
	Copy-Item -Path "$($unityBundleProjectPath)\Assets\AssetBundles\$assetFileName" -Destination $targetPath -Force -Confirm:$false
	Copy-Item -Path "$($unityBundleProjectPath)\Assets\AssetBundles\$($assetFileName).manifest" -Destination $targetPath -Force -Confirm:$false
	WriteMessage -success "Created AssetBundle for $($modObject.Name) at $targetPath"
}

function Update-ModAssetBundle {
	param(
		$modObject,
		[switch]$check,
		[switch]$update,
		[switch]$force
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return $false
		}
	}

	if (-not $modObject.ModFolderPath) {
		WriteMessage -failure "$($modObject.Name) does not have a folder defined"
		return $false
	}

	if (-not (Test-Path $modObject.ModFolderPath)) {
		WriteMessage -failure "Mod folder does not exist: $($modObject.ModFolderPath)"
		return $false
	}

	if ($modObject.MetadataFileJson.OnDemandBundleUpdate -and -not $force) {
		WriteMessage -message "$($modObject.Name) is set to OnDemandBundleUpdate, skipping AssetBundle creation"
		return $true
	}

	if ($modObject.ModIconPath -and $modObject.ModIconPath.StartsWith("$($modObject.ModFolderPath)\Textures")) {
		WriteMessage -progress "Moving modicon back from Textures to About-folder"
		Move-Item $modObject.ModIconPath "$($modObject.ModFolderPath)\About\ModIcon.png" -Confirm:$false -Force
		$modObject.ModIconPath = "$($modObject.ModFolderPath)\About\ModIcon.png"

		if (-not (Get-ChildItem "$($modObject.ModFolderPath)\Textures" -Recurse -File)) {
			WriteMessage -progress "Removing now empty Textures-folder"
			Remove-Item "$($modObject.ModFolderPath)\Textures" -Recurse -Force -Confirm:$false -ProgressAction SilentlyContinue
		}

		if ($modObject.aboutFileXml.ModMetaData.modIconPath) {
			WriteMessage -progress "Removing modIconPath from about-file"
			$modObject.aboutFileXml.ModMetaData.RemoveChild($modObject.aboutFileXml.ModMetaData.modIconPath) | Out-Null
			$modObject.aboutFileXml.Save($modObject.AboutFilePath)
		}

		WriteMessage -success "Reverted mod-icon from Textures to About-folder"
	}

	$createBundle = $false
	if ($modObject.UsesAssetBundle) {
		if ($check) {
			return $true
		}
		if ($update) {
			$assetFiles = Get-ChildItem -Path $modObject.AssetSourcePath -Recurse -File
			$latestChangedFile = $assetFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
			$bundleFiles = Get-ChildItem -Path $modObject.AssetBundlesPath -Recurse -File
			$latestChangedBundle = $bundleFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1

			if ($latestChangedFile -and $latestChangedBundle -and $latestChangedFile.LastWriteTime -le $latestChangedBundle.LastWriteTime -and -not $force) {
				WriteMessage -message "No asset files have changed since the last AssetBundle creation for $($modObject.Name), skipping AssetBundle creation"
			} else {
				if (-not $force) {
					WriteMessage -progress "Asset files have changed since the last AssetBundle creation for $($modObject.Name), proceeding with AssetBundle creation"
				}
				$createBundle = $true
			}
		}
	} else {
		$assetFolderNames = @("Textures", "Sounds")
		$assetFolders = Get-ChildItem -Path $modObject.ModFolderPath -Directory | Where-Object { $_.Name -in $assetFolderNames }
		if (-not $assetFolders) {
			WriteMessage -message "No asset folders found in $($modObject.ModFolderPath), skipping AssetBundle creation"
			return $true
		}

		$assetFiles = $assetFolders | ForEach-Object { Get-ChildItem -Path $_.FullName -Recurse -File }

		if ($assetFiles.Count -lt $assetCountLimit -and -not $force) {
			WriteMessage -success "Asset files found in $($modObject.ModFolderPath) was $($assetFiles.Count), below limit of $assetCountLimit, skipping AssetBundle creation"
			return $true
		}

		$noLegacy = $false
		$assetSize = ($assetFiles | Measure-Object -Property Length -Sum | Select-Object -ExpandProperty Sum)
		if ($assetSize -gt $assetSizeLimit) {
			if (-not $force) {
				WriteMessage -failure "Total size of asset files in $($modObject.ModFolderPath) is $([math]::Round($assetSize / 1MB, 2)) Mb, exceeding the limit of $assetSizeLimitMb, skipping AssetBundle creation"
				return $false
			}
			$noLegacy = $true
		}

		WriteMessage -success "Asset files found in $($modObject.ModFolderPath) ($([math]::Round($assetSize / 1MB, 2)) Mb) was $($assetFiles.Count), exceeding limit of $assetCountLimit, proceeding with AssetBundle creation"

		if ($check) {
			return $true
		}
		$modObject.AssetBundlesPath = "$($modObject.ModFolderPath)\AssetBundles"
		$modObject.AssetSourcePath = "$($modObject.ModFolderPath)\Source\Assets"

		if ($modObject.SupportedVersions -contains "1.5" -and -not $noLegacy) {
			$modObject.AssetBundlesPath = "$($modObject.ModFolderPath)\Assets\AssetBundles"
			$modObject.AssetSourcePath = "$($modObject.ModFolderPath)\LegacyAssets"
		}

		if ( -not (Test-Path $modObject.AssetBundlesPath)) {
			WriteMessage -progress "Creating AssetBundle-folder at $($modObject.AssetBundlesPath)"
			New-Item -Path $modObject.AssetBundlesPath -ItemType Directory -Force | Out-Null
		}
		if (-not (Test-Path $modObject.AssetSourcePath)) {
			WriteMessage -progress "Creating AssetSource-folder at $($modObject.AssetSourcePath)"
			New-Item -Path $modObject.AssetSourcePath -ItemType Directory -Force | Out-Null
		}

		WriteMessage -progress "Moving old assets to $($modObject.AssetSourcePath)"
		$assetFolders | ForEach-Object {
			Move-Item -Path $_.FullName -Destination $modObject.AssetSourcePath -Force -Confirm:$false
		}
		$createBundle = $true
	}

	if ($createBundle) {
		WriteMessage -progress "Creating AssetBundle for $($modObject.Name)"
		New-AssetBundle -modObject $modObject
		$modObject = Get-Mod -originalModObject $modObject
	}

	if (-not $modObject.UsesRegularAssets) {
		return $true
	}

	if (-not $modObject.LoadFoldersPath) {
		WriteMessage -progress "Verifying LoadFolders.xml for $($modObject.Name)"
		$loadFoldersPath = "$($modObject.ModFolderPath)\LoadFolders.xml"
		'<?xml version="1.0" encoding="utf-8"?><loadFolders></loadFolders>' > $loadFoldersPath
		$modObject.LoadFoldersPath = $loadFoldersPath
	}
	$loadFoldersXml = [xml](Get-Content $modObject.LoadFoldersPath -Raw -Encoding UTF8)
	foreach ($version in $modObject.SupportedVersions) {
		if (-not $loadFoldersXml.DocumentElement."v$version") {
			$versionNode = $loadFoldersXml.CreateElement("v$version")
			$rootLi = $loadFoldersXml.CreateElement("li")
			$rootLi.InnerText = "/"
			$versionNode.AppendChild($rootLi) | Out-Null
			if (Test-Path "$($modObject.ModFolderPath)\$version") {
				$versionLi = $loadFoldersXml.CreateElement("li")
				$versionLi.InnerText = "$version"
				$versionNode.AppendChild($versionLi) | Out-Null
			}
			$loadFoldersXml.DocumentElement.AppendChild($versionNode) | Out-Null
		}
		$versionNode = $loadFoldersXml.DocumentElement."v$version"
		$assetsFolderName = "LegacyAssets"
		if (([version]$version) -gt [version]"1.5") {
			$assetsFolderName = "Assets"
		}

		$hasAssetsLi = $false
		foreach ($li in $versionNode.SelectNodes("li")) {
			if ($li.InnerText -eq $assetsFolderName) {
				$hasAssetsLi = $true
				break
			}
		}
		if ($hasAssetsLi) {
			continue
		}

		$assetsLi = $loadFoldersXml.CreateElement("li")
		$assetsLi.InnerText = $assetsFolderName
		$versionNode.AppendChild($assetsLi) | Out-Null
		$loadFoldersXml.Save($modObject.LoadFoldersPath)
		WriteMessage -progress "Added $assetsFolderName to version $version in LoadFolders.xml for $($modObject.Name)"
	}

	WriteMessage -success "AssetBundle verified for $($modObject.Name) at $($modObject.AssetBundlesPath)"
	return $true
}

#endregion

#region Translations

# Translation of files
function Update-Translations {
	[CmdletBinding()]
	param (
		$modObject,
		[switch]$skipDefInject,
		[switch]$test,
		[switch]$silent,
		[switch]$force
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not $modObject.Mine -and -not $force) {
		WriteMessage -failure "$($modObject.Name) is not mine, aborting update"
		return
	}

	if ((Get-DeeplRemainingCharacters) -lt 1000) {
		WriteMessage -failure "Not enough characters left for translation, skipping $($modObject.Name)"
		return
	}

	if (-not $skipDefInject) {
		$translationTemplateFolderPath = "$($modObject.ModFolderPath)\Source\TranslationTemplate"
		$defInjectBaseFolderPath = "$($modObject.ModFolderPath)\Languages"

		if (Test-Path $translationTemplateFolderPath) {
			$translationTemplateFiles = Get-ChildItem -Path $translationTemplateFolderPath -Recurse -File
		}
		if ($translationTemplateFiles -and -not $modObject.MetadataFileJson.SkipDefInjectTranslations) {
			WriteMessage -progress "Updating defInject translations for $($modObject.Name)"
			if (-not (Test-Path $defInjectBaseFolderPath)) {
				New-Item -Path $defInjectBaseFolderPath -ItemType Directory -Force | Out-Null
			}

			$languagesToTranslate = $autoTranslateLanguages
			Get-ChildItem -Path $defInjectBaseFolderPath -Directory | ForEach-Object {
				if ($languagesToTranslate -notcontains $_.Name) {
					WriteMessage -progress "Adding existing language $($_.Name) to the list of languages to translate"
					$languagesToTranslate += $_.Name
				}
			}
			$progressObject = WriteProgress -initiate -title "Updating DefInject translations" -totalActions ($languagesToTranslate.Count * $translationTemplateFiles.Count)
			foreach ($language in $languagesToTranslate) {
				if ($modObject.MetadataFileJson.SkipLanguages -contains $language) {
					WriteMessage -progress "Mod is set to skip autotranslation to $language"
					$progressObject.current += $translationTemplateFiles.Count
					continue
				}
				if ($language -eq "English") {
					WriteMessage -progress "Skipping English, no point in translating it"
					$progressObject.current += $translationTemplateFiles.Count
					continue
				}
				$languageUpdated = $false
				$currentPath = "$($defInjectBaseFolderPath)\$language\DefInjected"
				if (-not (Test-Path $currentPath)) {
					WriteMessage -progress "No DefInjected folder found for $language, creating"
					New-Item $currentPath -ItemType Directory -Force | Out-Null
				}

				foreach ($file in $translationTemplateFiles) {
					WriteProgress -progressObject $progressObject
					$targetFilePath = $file.FullName.Replace($translationTemplateFolderPath, $currentPath)
					$targetFolder = Split-Path $targetFilePath
					if (-not (Test-Path $targetFolder)) {
						WriteMessage -progress "Creating $targetFolder"
						New-Item -Path $targetFolder -ItemType Directory -Force | Out-Null
					}
					WriteMessage -progress "Updating $($file.Name) for $language"
					if (Update-TranslationFile -sourceFilePath $file.FullName -targetFilePath $targetFilePath -language $language -modObject $modObject -test:$test) {
						$languageUpdated = $true
					}
				}

				if ($languageUpdated -and $language -notin $updatedLanguages) {
					$updatedLanguages += $language
				}
			}
			WriteProgress -progressObject $progressObject -finished
		}
	}
	$allLanguagesFolders = Get-ChildItem -Path $modObject.ModFolderPath -Recurse -Include "Languages" -Directory
	if (-not $allLanguagesFolders) {
		if (-not $silent) {
			WriteMessage -progress "No translation needed for $($modObject.Name), ignoring"
		}
		return
	}

	$updatedLanguages = @()

	foreach ($folder in $allLanguagesFolders) {
		if (-not (Test-Path "$($folder.FullName)\English\Keyed")) {
			continue
		}
		$keyedSourceFiles = Get-ChildItem -Path "$($folder.FullName)\English\Keyed" -File

		if (-not $keyedSourceFiles) {
			WriteMessage -warning "$($modObject.Name) has empty translation-folder: $($folder.FullName)\English\Keyed"
			continue
		}

		foreach ($language in $autoTranslateLanguages) {
			if ($modObject.MetadataFileJson.SkipLanguages -contains $language) {
				WriteMessage -progress "Mod is set to skip autotranslation to $language"
				continue
			}
			if (-not (Test-Path "$($folder.FullName)\$language")) {
				WriteMessage -progress "No translation found for $language, autocreating"
				New-Item "$($folder.FullName)\$language" -ItemType Directory | Out-Null
			}
		}

		$allNonEnglishFolders = Get-ChildItem -Path $folder.FullName -Directory -Exclude "English"
		if (-not $allNonEnglishFolders) {
			continue
		}

		$progressObject = WriteProgress -initiate -title "Updating translations" -totalActions ($allNonEnglishFolders.Count * $keyedSourceFiles.Count)
		foreach ($languageFolder in $allNonEnglishFolders) {
			if ($languages -notcontains $languageFolder.Name) {
				WriteMessage -warning "$($languageFolder.Name) can not be translated by DeepL"
				$progressObject.current += $keyedSourceFiles.Count
				continue
			}
			$keyedFolder = "$($languageFolder.FullName)\Keyed"
			if (-not (Test-Path $keyedFolder)) {
				WriteMessage -progress "No translation found for $($languageFolder.Name), autocreating"
				New-Item "$($languageFolder.FullName)\Keyed" -ItemType Directory | Out-Null
			}
			$languageUpdated = $false
			foreach ($file in $keyedSourceFiles) {
				WriteProgress -progressObject $progressObject
				$targetFilePath = "$keyedFolder\$($file.Name)"
				WriteMessage -progress "Updating $($file.Name) for $($languageFolder.Name)"
				if (Update-TranslationFile -sourceFilePath $file.FullName -targetFilePath $targetFilePath -language $languageFolder.Name -modObject $modObject -test:$test) {
					$languageUpdated = $true
				}
			}
			if ($languageUpdated -and $languageFolder.Name -notin $updatedLanguages) {
				$updatedLanguages += $languageFolder.Name
			}
		}
		WriteProgress -progressObject $progressObject -finished
	}
	if ($updatedLanguages.Length -gt 0) {
		$updatedLanguages = $updatedLanguages | Get-Unique
		$charsLeft = Get-DeeplRemainingCharacters
		if ($charsLeft -gt 10000) {
			WriteMessage "Remaining DeepL characters: $charsLeft/500000" -progress
		} elseif ($charsLeft -gt 1000) {
			WriteMessage "Remaining DeepL characters: $charsLeft/500000" -warning
		} else {
			WriteMessage "Remaining DeepL characters: $charsLeft/500000" -failure
		}
		return "Used DeepL to update translations for $($updatedLanguages -join ", ")"
	}
}

function Update-TranslationFile {
	[CmdletBinding()]
	param(
		$sourceFilePath,
		$targetFilePath,
		$language,
		$modObject,
		[switch]$test
	)

	# Check if the source file path contains RulePackDef, if so skip it
	if ($sourceFilePath -match "RulePackDef") {
		WriteMessage -progress "Skipping RulePackDef file: $sourceFilePath"
		return $true
	}

	$baseXml = @"
<?xml version="1.0" encoding="utf-8"?>
"@
	$context = "This text is from the mod $($modObject.DisplayName)."
	$fileName = Split-Path -Leaf $sourceFilePath
	$translateTo = $shorts[$languages.IndexOf($language)]
	if (-not (Test-Path $targetFilePath)) {
		WriteMessage -warning "$($modObject.Name) has missing translation-file: '$targetFilePath'. Creating."
		WriteMessage -progress "Creating $fileName for $language in $($modObject.Name)"
		$baseXml | Out-File -FilePath $targetFilePath -Encoding utf8
	}
	$commentExists = $false
	if (Select-String -Path $targetFilePath -Pattern "DeepL") {
		$commentExists = $true
	}
	$sourceContent = [xml](Get-Content -Path $sourceFilePath -Encoding utf8)
	$targetContent = [xml](Get-Content -Path $targetFilePath -Encoding utf8)
	if (-not $targetContent.LanguageData) {
		$languageData = $targetContent.CreateElement("LanguageData")
		$targetContent.AppendChild($languageData) | Out-Null
	}

	if (-not $test) {
		$remainingChars = Get-DeeplRemainingCharacters
		if ($remainingChars -lt 250) {
			WriteMessage -failure "There are not enough credits left to translate, $remainingChars left."
			return $false
		}
		Start-Sleep -Milliseconds 500
	}

	$resaveFile = $false
	$nodeCount = 0
	foreach ($childNode in $sourceContent.LanguageData.ChildNodes) {
		$nodeCount++
		if ($targetContent.LanguageData."$($childNode.Name)") {
			if ($childNode.NodeType -ne "Comment") {
				# Check if the node text contains {} and if they do not match, open the file in a text editor and warn the user
				$sourceText = "$($childNode.'#text')"
				$targetText = "$($targetContent.LanguageData."$($childNode.Name)").'#text')"
				if ($sourceText -match "\{.*\}" -and $targetText -notmatch "\{.*\}") {
					$applicationPath = $settings.text_editor_path
					$arguments = """$targetFilePath"""
					Start-Process -FilePath $applicationPath -ArgumentList $arguments
					WriteMessage -warning "Mismatched placeholders in node $nodeCount with name $($childNode.Name) in $targetFilePath. Opened file for manual fixing."
					ReadHost -query "Press Enter to continue after fixing the file"
					continue
				}

				Write-Debug "Node $nodeCount with name $($childNode.Name) already exists in $targetFilePath, skipping"
				continue
			}
			if ($targetContent.LanguageData.ChildNodes | Where-Object { $_.Name -eq "#comment" -and $_.Value -eq $childNode.Value }) {
				Write-Debug "Comment $($childNode.Value) already exists in $targetFilePath, skipping"
				continue
			}
		}
		if (-not $commentExists) {
			$commentExists = $true
			if ($test) {
				WriteMessage -progress "Would have added a DeepL translation-comment to $targetFilePath"
			} else {
				WriteMessage -progress "Adding DeepL translation-comment to $targetFilePath"
				$comment = $targetContent.CreateComment("The following translations were generated by https://www.deepl.com/")
				if ($targetContent.LanguageData.ChildNodes) {
					$targetContent.LanguageData.AppendChild($comment) | Out-Null
				} else {
					$targetContent.DocumentElement.AppendChild($comment) | Out-Null
				}
			}
		}
		if ($childNode.NodeType -eq "Comment") {
			$comment = $targetContent.CreateComment($childNode.Value)
			if ($targetContent.LanguageData.ChildNodes) {
				$targetContent.LanguageData.AppendChild($comment) | Out-Null
			} else {
				$targetContent.DocumentElement.AppendChild($comment) | Out-Null
			}
			$resaveFile = $true
			continue
		}
		$textToTranslate = "$($childNode.'#text')"
		$cdata = $false
		if (-not $textToTranslate) {
			$textToTranslate = $childNode.'#cdata-section'
			$cdata = $true
		}
		if (-not $textToTranslate) {
			WriteMessage -progress "Could not figure out text to translate for child node $nodeCount in $($file.Name)"
			continue
		}
		if ($textToTranslate -notmatch "{ ") {
			if ($test) {
				WriteMessage -progress "Would have translated '$textToTranslate' to $translateTo and added it to $targetFilePath"
				continue
			}
			$translatedString = Get-DeeplTranslation -text $textToTranslate -selectedTo $translateTo -silent:$silent -context $context
		} else {
			$textStrings = @()
			$numbers = @()
			foreach ($part in $textToTranslate.Split("{ ")) {
				if (-not $part) {
					$textStrings += "<"
					continue
				}
				if ($part -notmatch "}") {
					$textStrings += $part
					continue
				}
				if ($part.Split("}")[1]) {
					$textStrings += $part.Split("
    }")[1]
				}
				$numbers += $part.Split("
   }")[0]
			}
			if ($test) {
				WriteMessage -progress "Would have translated '$textToTranslate', a $($textStrings.Length) part string to $translateTo and added it to $targetFilePath. Strings: $textStrings, Numbers: $numbers"
				continue
			}
			if ($textStrings[0] -eq "<") {
				$translatedString = ""
			} else {
				$translatedString = Get-DeeplTranslation -text $textStrings[0] -selectedTo $translateTo -silent:$silent -context $context
			}
			for ($i = 0; $i -lt $numbers.Count; $i++) {
				$translatedString += " { $($numbers[$i]) }"
				if ($textStrings[$i + 1] -and $textStrings[$i + 1] -ne "<") {
					$translatedString += Get-DeeplTranslation -text $textStrings[$i + 1] -selectedTo $translateTo -silent:$silent -context $context
				}
			}
		}
		if (-not $textToTranslate.EndsWith(" ")) {
			$translatedString = $translatedString.Trim()
		}
		if (-not $translatedString) {
			continue
		}
		$nodeToAdd = $targetContent.CreateElement($childNode.Name)
		if ($cdata) {
			$textToAddToNode = $targetContent.CreateCDataSection($translatedString)
		} else {
			$textToAddToNode = $targetContent.CreateTextNode($translatedString)
		}
		$nodeToAdd.AppendChild($textToAddToNode) | Out-Null
		$targetContent.LanguageData.AppendChild($nodeToAdd) | Out-Null
		$resaveFile = $true
	}
	if ($resaveFile) {
		if ($test) {
			WriteMessage -progress "Would have saved $targetFilePath"
			return $false
		}
		WriteMessage -success "Added automatic translations to $targetFilePath"
		$targetContent.Save($targetFilePath)
		return $true
	}
	return $false
}


# Generates the DeepL header for requests
function Get-DeeplAuthorizationHeader {
	$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
	$header.Add('Authorization', "DeepL-Auth-Key $deeplApiKey")
	return $header
}

# Gets remaining characters to use from the DeepL service
function Get-DeeplRemainingCharacters {
	while ($true) {
		try {
			$result = Invoke-RestMethod -Method "POST" -Headers (Get-DeeplAuthorizationHeader) -Uri "$deeplApiUrl/v2/usage"
			break
		} catch {
			WriteMessage -failure "Sleeping for 1 seconds"
			Start-Sleep -Seconds 1
		}
	}

	return $result.character_limit - $result.character_count
}

# Translation using https://www.deepl.com/
function Get-DeeplTranslation {
	param (
		$text,
		$selectedFrom,
		$selectedTo,
		$context,
		[switch]$chooseLanguage,
		[switch]$silent
	)

	if (-not $text) {
		WriteMessage -failure "No text defined, skipping"
		return
	}

	if (-not ($text -match '[a-zA-Z]')) {
		WriteMessage -warning "$text does not contain words, will not translate"
		return $text
	}

	if ($selectedTo -and -not $selectedFrom) {
		$selectedFrom = "EN"
	}
	if (-not $selectedTo -and -not $selectedFrom) {
		if (-not $chooseLanguage) {
			if (-not $silent) {
				WriteMessage -progress "Assuming translation to English using auto recognize original language"
			}
			$selectedFrom = "AUTO"
			$selectedTo = "EN-US"
		} else {
			for ($i = 0; $i -lt $languages.Count; $i++) {
				Write-Host "$($i + 1): $($languages[$i])"
			}
			$answer = ReadHost "Select FROM language (empty is auto)"
			if ($answer) {
				$selectedFrom = $shorts[$answer - 1]
			} else {
				$selectedFrom = "AUTO"
			}
			for ($i = 0; $i -lt $languages.Count; $i++) {
				Write-Host "$($i + 1): $($languages[$i])"
			}
			$answer = ReadHost "Select TO language (REQUIRED)"
			if (-not $answer) {
				WriteMessage -failure "You need to select a target language"
				return
			}
			$selectedTo = $shorts[$answer - 1]
		}
	}

	$urlSuffix = "?target_lang=$selectedTo"
	if ($selectedFrom -ne "AUTO") {
		if ($selectedFrom -eq "EN-US") {
			$selectedFrom = "EN"
		}
		if ($selectedFrom -eq "EN-GB") {
			$selectedFrom = "EN"
		}
		if ($selectedFrom -eq "PT-PT") {
			$selectedFrom = "PT"
		}
		if ($selectedFrom -eq "PT-BR") {
			$selectedFrom = "PT"
		}

		$urlSuffix += "&source_lang=$selectedFrom"
	}

	$translatedText = Get-TranslationFromCacheDb -Text $text -TargetLang $selectedTo
	if ($translatedText) {
		WriteMessage -progress "Cache hit for '$text' to $selectedTo"
		return $translatedText
	}

	$urlSuffix += "&text=$text"
	$baseContext = "Translation of user-facing text for things in the game RimWorld."
	if ($context) {
		$baseContext = "$baseContext $context"
	}
	$urlSuffix += "&context=$baseContext"

	WriteMessage -progress "Translating '$text' from $selectedFrom to $selectedTo"

	Start-Sleep -Milliseconds 250
	while ($true) {
		try {
			$result = Invoke-RestMethod -Method "POST" -Headers (Get-DeeplAuthorizationHeader) -Uri "$deeplApiUrl/v2/translate$urlSuffix"
			break
		} catch {
			WriteMessage -failure "Sleeping for 1 seconds"
			Start-Sleep -Seconds 1
		}
	}

	$result = $result.translations.text
	Set-TranslationInCacheDb -Text $text -Translation $result -TargetLang $selectedTo | Out-Null
	return $result
}

# Deprecated
# Generates default language files for english
# Uses rimtrans from https://github.com/Aironsoft/RimTrans
function Set-Translation {
	param (
		$modObject,
		[switch] $force
	)

	WriteMessage -failure "RimTrans is not working at the moment"
	return

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	if (-not $modObject.Mine -and -not $force) {
		WriteMessage -failure "$($modObject.Name) is not mine, aborting update"
		return
	}

	$logFile = "E:\ModPublishing\Binaries\update.log"
	$currentLogTime = (Get-Item $logFile).LastWriteTime
	Update-LocalBinaries

	$rimTransExe = $settings.rimtrans_path
	$currentFile = $rimTransTemplate.Replace(".xml", "_current.xml")
	$command = "-p:$currentFile"

	if ((Get-Item $logFile).LastWriteTime -ne $currentLogTime) {
		WriteMessage -progress "Copying game-files to RimTrans path"
		Copy-Item "E:\ModPublishing\Binaries\*.dll" (Split-Path $rimTransExe) -Force
		return
	}

	WriteMessage -progress "Generating default language-data"

	(Get-Content $rimTransTemplate -Raw -Encoding UTF8).Replace("[modpath]", $modObject.ModFolderPath) | Out-File $currentFile -Encoding utf8

	$process = Start-Process -FilePath $rimTransExe -ArgumentList $command -PassThru
	Start-Sleep -Seconds 1
	$wshell = New-Object -ComObject wscript.shell;
	$wshell.AppActivate('RimTrans')
	$wshell.SendKeys('{ ENTER }')
	while (-not $process.HasExited) {
		Start-Sleep -Milliseconds 200
	}
	WriteMessage -success "Generation done"
	Remove-Item -Path $currentFile -Force -ProgressAction SilentlyContinue
}

#endregion

#region Trello functions
function Get-TrelloBoards {
	$boards = Invoke-RestMethod -Uri "https://api.trello.com/1/members/me/boards?key=$trelloKey&token=$trelloToken" -Verbose:$false
	return $boards
}

function Get-TrelloCards {
	param(
		$boardId,
		$listId
	)
	if (-not $boardId) {
		$boardId = $trelloBoardId
	}
	if ($listId) {
		$cards = Invoke-RestMethod -Uri "https://api.trello.com/1/lists/$($listId)/cards?key=$trelloKey&token=$trelloToken&customFieldItems=true" -Verbose:$false
		return $cards
	}
	$cards = Invoke-RestMethod -Uri "https://api.trello.com/1/boards/$boardId/cards/open?key=$trelloKey&token=$trelloToken&customFieldItems=true" -Verbose:$false
	return $cards
}

function Get-TrelloCard {
	param($cardId)
	$card = Invoke-RestMethod -Uri "https://api.trello.com/1/cards/$($cardId)?key=$trelloKey&token=$trelloToken&customFieldItems=true" -Verbose:$false
	return $card
}

function New-TrelloCard {
	param($cardName, $listId)
	$card = Invoke-RestMethod -Uri "https://api.trello.com/1/cards?name=$cardName&idList=$listId&key=$trelloKey&token=$trelloToken" -Method Post -Verbose:$false
	return $card
}

function Get-TrelloList {
	param($listId)
	$list = Invoke-RestMethod -Uri "https://api.trello.com/1/lists/$($listId)?key=$trelloKey&token=$trelloToken" -Verbose:$false
	return $list
}

function Get-TrelloListActions {
	param($listId)
	$actions = Invoke-RestMethod -Uri "https://api.trello.com/1/lists/$($listId)/actions?key=$trelloKey&token=$trelloToken" -Verbose:$false
	return $actions
}

function Get-TrelloCardActions {
	param($cardId)
	$actions = Invoke-RestMethod -Uri "https://api.trello.com/1/cards/$($cardId)/actions?key=$trelloKey&token=$trelloToken" -Verbose:$false
	return $actions
}

function Add-TrelloCardComment {
	param($cardId, $comment)
	$comment = [uri]::EscapeDataString($comment)
	Invoke-RestMethod -Method Post -Uri "https://api.trello.com/1/cards/$($cardId)/actions/comments?key=$trelloKey&token=$trelloToken&text=$comment" -Verbose:$false | Out-Null
}

function Add-TrelloCardLabel {
	param($cardId, $labelId)

	$body = @"
{
    "value": "$labelId"
}
"@
	Invoke-RestMethod -Method Post -Body $body -ContentType 'application/json' -Uri "https://api.trello.com/1/cards/$($cardId)/idLabels?key=$trelloKey&token=$trelloToken" -Verbose:$false | Out-Null
}

function Set-TrelloCardToArchived {
	param($cardId)

	$body = @"
{
    "closed": "true"
}
"@
	Invoke-RestMethod -Method Put -Body $body -ContentType 'application/json' -Uri "https://api.trello.com/1/cards/$($cardId)?key=$trelloKey&token=$trelloToken" -Verbose:$false | Out-Null
}

function Find-TrelloCardByName {
	param ($text)
	$cards = Get-TrelloCards -boardId $trelloBoardId
	$cards | ForEach-Object { if ($_.name.contains($text)) {
			return $_
		} }
}

function Find-TrelloCardByCustomField {
	param (
		$text,
		$fieldId
	)
	$cards = Get-TrelloCards -boardId $trelloBoardId
	$cards | ForEach-Object { if ($_.customFieldItems -and $_.customFieldItems.idCustomField.contains($fieldId)) {
			if (($_.customFieldItems | Where-Object { $_.idCustomField -eq $fieldId }).value.text.StartsWith($text) ) {
				return $_
			}
		}
	}
}

function Get-TrelloCardsForMod {
	param($modObject)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	WriteMessage -progress "Searching for Trello cards for mod $($modObject.Name) using Steam link"
	$cardsFromSteamUrl = Find-TrelloCardByCustomField -text $modObject.ModUrl -fieldId $trelloLinkId
	WriteMessage -progress "Searching for Trello cards for mod $($modObject.Name) using Github link"
	$cardsFromGithubUrl = Find-TrelloCardByCustomField -text $modObject.Repository -fieldId $trelloLinkId
	WriteMessage -progress "Found $($cardsFromGithubUrl.Count + $cardsFromSteamUrl.Count) Trello cards for mod $($modObject.Name)"

	$returnArray = @()
	if ($cardsFromSteamUrl) {
		$returnArray += $cardsFromSteamUrl
	}
	if ($cardsFromGithubUrl) {
		$returnArray += $cardsFromGithubUrl
	}
	return $returnArray
}

function Get-ModIssues {
	param($modObject)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	$issues = Get-TrelloCardsForMod -modObject $modObject
	if (-not $issues) {
		WriteMessage -progress "No issues found for mod $($modObject.Name)"
		return
	}

	WriteMessage -progress "Found $($issues.Count) issues for mod $($modObject.Name)"
	$issues | ForEach-Object {
		$lastUpdated = $(Get-Date $_.dateLastActivity)
		Write-Host "`n$($lastUpdated.ToString("yyyy-MM-dd HH:mm:ss")) ( $($_.shortUrl) )"
		Write-Host -ForegroundColor DarkGray "$($_.desc)`n"
	}
}

function Close-TrelloCardsForMod {
	param(
		$modObject,
		[switch]$justMajorVersion,
		[switch]$closeAll
	)

	if (-not $modObject) {
		$modObject = Get-Mod
		if (-not $modObject) {
			return
		}
	}

	$foundCards = Get-TrelloCardsForMod -modObject $modObject

	if (-not $foundCards) {
		WriteMessage -progress "No active Trello cards found for mod"
		return
	}

	if ($justMajorVersion) {
		foreach ($card in $foundCards) {
			if ($card.idList -ne $trelloMajorVersionList) {
				WriteMessage -progress "Ignoring card with url $($card.shortUrl) since its on the wrong list"
				continue
			}

			WriteMessage -success "Auto-closing $($card.name)"
			Set-TrelloCardToArchived -cardId $card.id
		}
		return
	}

	WriteMessage -progress "Found $($foundCards.Count) active Trello cards for $($modObject.Name)"
	$counter = 1
	foreach ($card in $foundCards) {
		if ($closeAll) {
			Write-Host -ForegroundColor Green "`nClosing $($card.name) ( $($card.shortUrl) )"
			Set-TrelloCardToArchived -cardId $card.id
			continue
		}
		Write-Host -ForegroundColor Green "`n$counter - $($card.name) ( $($card.shortUrl) )`n$($card.desc)`n"
		$counter++
	}

	if ($closeAll) {
		return
	}

	$selection = ReadHost "What card(s) do you want to close, select multiple separated by space"
	if (-not $selection) {
		WriteMessage -progress "No card chosen"
		return
	}

	foreach ($choice in $selection.Split(" ")) {
		$card = $foundCards[$choice - 1]
		WriteMessage -progress "Closing $($choice) - $($card.name) ($($card.dateLastActivity))"
		Set-TrelloCardToArchived -cardId $card.id
		if ($card.customFieldItems -and $card.customFieldItems.idCustomField.contains($trelloDiscordForumId)) {
			$discordLinkData = $card.customFieldItems | Where-Object { $_.idCustomField -eq $trelloDiscordForumId }
			$discordLink = $discordLinkData.value.text
			cmd.exe /c "start $discordLink"
		}

	}
	Start-Sleep -Seconds 1
	Remove-Item "$($modObject.ModFolderPath)\debug.log" -Force -ErrorAction SilentlyContinue
}


function Update-TrelloCardWithFile {
	param(
		$cardId,
		$filePath
	)

	if (-not $filePath -or -not (Test-Path $filePath)) {
		WriteMessage -warning "No file found at path $filePath"
		return
	}

	$fileName = "$((Get-Date).ToString("yyyy-MM-dd HH:mm:ss"))_$($filePath | Split-Path -Leaf)"
	$form = @{
		filename = $fileName
		file     = Get-Item $filePath
	}

	return Invoke-RestMethod -Method Post -Uri "https://api.trello.com/1/cards/$cardId/attachments?key=$trelloKey&token=$trelloToken" -Form $form
}
#endregion