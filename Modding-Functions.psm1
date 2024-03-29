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

# Shows the rimworld log progress
function Get-RimworldLog {	
	param(
		$initialRows = 10
	)
	Get-content "$env:USERPROFILE\Appdata\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Player.log" -Tail $initialRows -Wait
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
$Global:replacementsFile = "$PSScriptRoot\ReplaceRules.txt"
$Global:manifestTemplate = "$PSScriptRoot\$($settings.manfest_template)"
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
$Global:discordUpdateMessage = "$PSScriptRoot\$($settings.discord_update_message)"
$Global:discordPublishMessage = "$PSScriptRoot\$($settings.discord_publish_message)"
$Global:discordRemoveMessage = "$PSScriptRoot\$($settings.discord_remove_message)"
$Global:discordUpdateHookUrl = $settings.discord_update_hook_url
$Global:discordPublishHookUrl = $settings.discord_publish_hook_url
$Global:discordRemoveHookUrl = $settings.discord_remove_hook_url
$Global:discordTestHookUrl = $settings.discord_test_hook_url
$Global:discordHookUrl = $settings.discord_remove_hook_url
$Global:trelloKey = $settings.trello_api_key
$Global:trelloToken = $settings.trello_api_token
$Global:trelloBoardId = $settings.trello_board_id
$Global:deeplApiKey = $settings.deepl_api_key
$Global:autoTranslateLanguages = $settings.auto_translate_languages
if (-not (Test-Path "$($settings.mod_staging_folder)\..\modlist.json")) {
	"{}" | Out-File -Encoding utf8 -FilePath "$($settings.mod_staging_folder)\..\modlist.json"
}
$Global:modlist = Get-Content "$($settings.mod_staging_folder)\..\modlist.json" -Raw -Encoding UTF8 | ConvertFrom-Json
$Global:identifierCache = @{}
$Global:languages = @("Bulgarian", "Czech", "Danish", "German", "Greek", "English (British)", "English", "Spanish", "Estonian", "Finnish", "French", "Hungarian", "Indonesian", "Italian", "Japanese", "Lithuanian", "Latvian", "Dutch", "Polish", "Portuguese", "Portuguese (Brazilian)", "Romanian", "Russian", "Slovak", "Slovenian", "Swedish", "Turkish", "ChineseSimplified")
$Global:shorts = @("BG","CS","DA","DE","EL","EN-GB","EN-US","ES","ET","FI","FR","HU","ID","IT","JA","LT","LV","NL","PL","PT-PT","PT-BR","RO","RU","SK","SL","SV","TR","ZH")
$Global:faqText = $settings.faq_text
$Global:faqTextPrivate = $settings.faq_text_private

# Select folder dialog, for selecting mod-folder manually
Function Get-Folder($initialDirectory) {
	[System.Reflection.Assembly]::LoadWithPartialName("System.windows.forms") | Out-Null
	$folder = $false
	$foldername = New-Object System.Windows.Forms.FolderBrowserDialog
	$foldername.Description = "Select a folder"
	$foldername.rootfolder = "MyComputer"
	$foldername.SelectedPath = $localModFolder
	$foldername.ShowNewFolderButton = $false

	if ($foldername.ShowDialog() -eq "OK") {
		$folder = $foldername.SelectedPath
	}
	return $folder
}

# Converts BB-steam text to Github format
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
			$currentRow = Read-Host
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
		[string]$modName,
		[switch]$getLink,
		$extraParameters
	)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
	}
	if (-not $modName) {
		return
	}
	$modNameClean = $modName.Replace("+", "Plus")
	$arguments = "https://github.com/$($settings.github_username)/$modNameClean$($extraParameters)"
	if ($getLink) {
		return $arguments
	}	
	$applicationPath = $settings.browser_path
	Start-Process -FilePath $applicationPath -ArgumentList $arguments
	Start-Sleep -Seconds 1
	Remove-Item "$localModFolder\$modName\debug.log" -Force -ErrorAction SilentlyContinue
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
	WriteMessage -progress "Fetching status for $repoName"
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
		Read-Host "Get latest git-changes now? (Enter to fetch, all other breaks)"
	}
	$originalLocation = Get-Location
	if (Get-LocalModFolder -modName $repoName) {
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

	Write-Host "Active Pull Requests"
	for ($i = 0; $i -lt $openRequests.Count; $i++) {
		Write-Host "$($i + 1): $($openRequests[$i].title) by $($openRequests[$i].user.login) ($($openRequests[$i].created_at))"
	}
	Write-Host ""

	$answer = Read-Host "Select PR to merge or empty to exit"

	if (-not $answer -or -not $openRequests[$answer - 1]) {
		WriteMessage -progress "Aborting merge"
		return
	}
	$selectedPullRequest = $openRequests[$answer - 1]

	Write-Host "Selected PR $answer with id $($selectedPullRequest.id)"

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
	

	foreach ($repo in $repoNames) {
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

# Simple push function for git
function Push-ModContent {
	param(
		[switch]$reapplyGitignore,
		$message
	)
	if (-not $message) {
		$message = Read-Host "Commit-Message"
	}
	Set-SafeGitFolder
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
		[switch]$mineOnly,
		[switch]$newOnly,
		[switch]$clean,
		[switch]$force,
		[switch]$overwrite
	)
	$currentDirectory = (Get-Location).Path
	if ($force) {
		$modFolder = $currentDirectory
		$modName = Split-Path -Leaf $modFolder
	} else {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
		$modFolder = "$localModFolder\$modName"
		Set-Location $modFolder		
	}
	if ($clean) {
		Remove-Item "$modFolder\.git" -Recurse -Force -Confirm:$false
	}
	if (Test-Path "$modFolder\.git") {
		if ($newOnly) {
			return
		}
		Set-SafeGitFolder
		if ($overwrite) {
			WriteMessage -progress "Reseting git to remote state for $modName"
			git reset --hard HEAD
		}
		WriteMessage -progress "Fetching latest github for mod $modName"
		git pull origin main --allow-unrelated-histories
		return
	} 
	WriteMessage -progress "Fetching latest github for mod $modName"
	if (Get-OwnerIsMeStatus -modName $modName) {
		$path = Get-ModRepository -getLink
	}
	if (-not $path -and $mineOnly) {
		WriteMessage -failure "$modName is not my mod, exiting"
		return
	}
	if (-not $path -and (Get-RepositoryStatus -repositoryName $modName)) {
		$path = Get-ModRepository -getLink
	}
	if (-not $path) {
		$path = Read-Host "URL for the project"
	}

	if ((Get-ChildItem $modFolder).Length -gt 0) {
		git init
		git remote add origin $path
		git fetch
		git config core.autocrlf true
		git add -A
		Update-GitRepoName -modName $modName
		git pull origin main
	} else {
		git clone $path $modFolder
		Update-GitRepoName -modName $modName
	}
	Set-IssuesActive -repoName $modName -force:$force
}

# Sets the branch-name to main instead of master
function Update-GitRepoName {
	param (
		[string]$modName
	)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
	}
	if (-not $modName) {
		return
	}
	$path = Get-ModRepository -getLink
	Set-SafeGitFolder
	if (-not (git ls-remote --heads $path master)) {
		WriteMessage -failure "$modName does not use the 'master' branch name, exiting"
		return
	}
	git switch -f master
	git branch -m master main
	git push -u origin main
	#git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
	git branch -u origin/main main
	Set-DefaultGitBranch -repoName $modName.Replace("+", "Plus") -branchName "main"
	git push origin --delete master
}

# Merges a repository with another, preserving history
function Merge-GitRepositories {
	$modName = Get-CurrentModNameFromLocation
	if (-not $modName) {
		return
	}
	
	if (-not (Get-OwnerIsMeStatus -modName $modName)) {
		WriteMessage -failure "$modName is not mine, aborting merge"
		return
	}
	$modFolder = "$localModFolder\$modName"
	$manifestContent = [xml] (Get-Content "$modFolder\About\Manifest.xml" -Raw -Encoding UTF8)
	$stagingDirectory = $settings.mod_staging_folder
	$rootFolder = Split-Path $stagingDirectory
	$version = [version]$manifestContent.Manifest.version
	$newVersion = $version.ToString()

	Set-Location -Path $rootFolder
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse
	Set-Location -Path $stagingDirectory

	$modNameNew = $modName.Replace("+", "Plus")
	$modNameOld = "$($modNameNew)_Old"
	if (-not (Get-RepositoryStatus -repositoryName $modNameNew)) {
		WriteMessage -failure "No repository found for $modNameNew"
		Set-Location $currentDirectory
		return			
	}
	if (-not (Get-RepositoryStatus -repositoryName $modNameOld)) {
		WriteMessage -failure "No repository found for $modNameOld"
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
	git commit -S -m "Deleted obsolete files"
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


#endregion

#region File-functions

# Generates a new ModSync-file for a mod
function New-ModSyncFile {
	param (
		$targetPath,
		$modWebPath,
		$modname,
		$version
	)
	if (-not (Test-Path $modSyncTemplate)) {
		WriteMessage -failure "Cound not find ModSync-template: $($modSyncTemplate), skipping."
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
	if (-not $modName) {
		$currentDirectory = (Get-Location).Path
		if (-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
			WriteMessage -failure "Can only be run from somewhere under $localModFolder, exiting"
			return			
		}
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	}
	$modFolder = "$localModFolder\$modName"
	if (-not (Test-Path $modFolder)) {
		WriteMessage -failure "$modFolder can not be found, exiting"
		return	
	}
	if (-not (Get-OwnerIsMeStatus -modName $modName)) {
		WriteMessage -failure "$modName is not mine, aborting update"
		return
	}
	Set-Location $modfolder
	$files = Get-ChildItem . -Recurse
	foreach ($file in $files) { 
		if (-not $file.FullName.Contains("Textures")) {
			continue
		}
		if ($file.Extension -eq ".psd") {
			Move-Item $file.FullName "$localModFolder\$modName\Source\" -Force -Confirm:$false | Out-Null
			continue
		}
		$newName = $file.Name.Replace("_side", "_east").Replace("_Side", "_east").Replace("_front", "_south").Replace("_Front", "_south").Replace("_back", "_north").Replace("_Back", "_north").Replace("_rear", "_north").Replace("_Rear", "_north")
		$newPath = $file.FullName.Replace($file.Name, $newName)
		Move-Item $file.FullName "$newPath" -ErrorAction SilentlyContinue | Out-Null
	}
}


# Adds an update post to the mod
# If HugsLib is loaded this will be shown if new to user
# Also generates a Tabula Rasa update message of the same type
function Set-ModUpdateFeatures {
	param (
		[string] $modName,
		[string] $updateMessage,
		[switch] $Force
	)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}
	if (-not $Force -and -not (Get-OwnerIsMeStatus -modName $modName)) {
		WriteMessage -failure "$modName is not mine, aborting update"
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

	$modFileId = "$localModFolder\$modName\About\PublishedFileId.txt"
	$modId = Get-Content $modFileId -Raw -Encoding UTF8
	$updatefeaturesFileName = Split-Path $updatefeaturesTemplate -Leaf
	$updateinfoFileName = Split-Path $updateinfoTemplate -Leaf

	$updateFeaturesPath = "$localModFolder\$modName\News\$updatefeaturesFileName"
	$updateFeaturesFolder = Split-Path $updateFeaturesPath
	$updateinfoPath = "$localModFolder\$modName\$(Get-CurrentRimworldVersion)\Defs\$updateinfoFileName"
	if (-not (Test-Path "$localModFolder\$modName\$(Get-CurrentRimworldVersion)")) {
		$updateinfoPath = "$localModFolder\$modName\Defs\$updateinfoFileName"
	} 
	$updateinfoFolder = Split-Path $updateinfoPath

	if (-not (Test-Path $updateFeaturesFolder)) {
		New-Item -Path $updateFeaturesFolder -ItemType Directory -Force | Out-Null
	}
	if (-not (Test-Path $updateinfoFolder)) {
		New-Item -Path $updateinfoFolder -ItemType Directory -Force | Out-Null
	}
	if (-not (Test-Path $updateFeaturesPath)) {
		(Get-Content -Path $updatefeaturesTemplate -Raw -Encoding UTF8).Replace("[modname]", $modName).Replace("[modid]", $modId) | Out-File $updateFeaturesPath
	}
	if (-not (Test-Path $updateinfoPath)) {
		(Get-Content -Path $updateinfoTemplate -Raw -Encoding UTF8).Replace("[modname]", $modName).Replace("[modid]", $modId) | Out-File $updateinfoPath
	}
	Update-InfoBanner -modName $modName

	$manifestFile = "$localModFolder\$modName\About\Manifest.xml"
	$version = ([xml](Get-Content -path $manifestFile -Raw -Encoding UTF8)).Manifest.version
	$defName = "$($modName.Replace(" ", "_"))_$($version.Replace(".", "_"))"
	$newsObject = "	<HugsLib.UpdateFeatureDef ParentName=""$($modName)_UpdateFeatureBase"">
		<defName>$defName</defName>
		<assemblyVersion>$version</assemblyVersion>
		<content>$news</content>
	</HugsLib.UpdateFeatureDef>
</Defs>"
	(Get-Content -Path $updateFeaturesPath -Raw -Encoding UTF8).Replace("</Defs>", $newsObject) | Out-File $updateFeaturesPath

	$dateString = "$((Get-Date).Year)/$((Get-Date).Month)/$((Get-Date).Day)"
	$infoObject = "	<TabulaRasa.UpdateDef ParentName=""$($modName)_UpdateInfoBase"">
		<defName>$defName</defName>
		<date>$dateString</date>
		<content>$news</content>
	</TabulaRasa.UpdateDef>
</Defs>"
	(Get-Content -Path $updateinfoPath -Raw -Encoding UTF8).Replace("</Defs>", $infoObject) | Out-File $updateinfoPath
	
	WriteMessage -success "Added update news"
}


# Adds an changelog post to the mod
function Set-ModChangeNote {
	param (
		[string] $modName,
		[string] $Changenote,
		[switch] $Force
	)	
	if (-not $Force -and -not (Get-OwnerIsMeStatus -modName $modName)) {
		WriteMessage -failure "$modName is not mine, aborting update"
		return
	}
	$baseLine = "# Changelog for $modName"
	$changelogFilePath = "$localModFolder\$modName\About\Changelog.txt"
	if (-not (Test-Path $changelogFilePath)) {
		$baseLine  | Out-File $changelogFilePath
	}

	$replaceLine = "$baseLine

$Changenote
"
	(Get-Content -Path $changelogFilePath -Raw -Encoding UTF8).Replace($baseLine, $replaceLine) | Out-File $changelogFilePath -NoNewline
	WriteMessage -success "Added changelog"
}

# Restructures a mod-folder to use the correct structure
function Set-CorrectFolderStructure {
	param($modName)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}
	if (-not (Get-OwnerIsMeStatus -modName $modName)) {
		WriteMessage -failure "$modName is not mine, aborting update"
		return
	}
	$modFolder = "$localModFolder\$modName"
	
	$aboutFile = "$modFolder\About\About.xml"
	if (-not (Test-Path $aboutFile)) {
		WriteMessage -warning "No about-file for $modName"
		return
	}
	if (-not (Test-Path "$modFolder\About\PublishedFileId.txt")) {
		WriteMessage -warning  "$modName is not published"
		return
	}
	if (Test-Path "$modFolder\LoadFolders.xml") {
		WriteMessage -warning "$modName has a LoadFolder.xml, will not change folders"
		return
	}
	
	$currentVersions = Get-ModVersionFromAboutFile -aboutFilePath $aboutFile
	$missingVersionFolders = @()
	$subfolderNames = @()
	foreach	($version in $currentVersions) {
		if (Test-Path "$modFolder\$version") {
			$childFolders = Get-ChildItem "$modFolder\$version" -Directory
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
		WriteMessage -success "$modName has correct folder structure"
		return
	}
	if ($missingVersionFolders.Length -gt 1) {
		WriteMessage -warning "$modName has $($missingVersionFolders.Length) missing version-folders, cannot fix automatically"
		return	
	}
	WriteMessage -progress "$modName has missing version-folder: $($missingVersionFolders -join ",")"
	WriteMessage -progress "Will move the following folders to missing version-folder: $($subfolderNames -join ",")"
	foreach ($missingVersionFolder in $missingVersionFolders) {
		New-Item -Path "$modFolder\$missingVersionFolder" -ItemType Directory -Force | Out-Null
		foreach ($subfolderName in $subfolderNames) {
			if (Test-Path "$modFolder\$subfolderName") {
				Move-Item -Path "$modFolder\$subfolderName" -Destination "$modFolder\$missingVersionFolder\$subfolderName" -Force | Out-Null
			} else {
				WriteMessage -progress "$modFolder\$subfolderName doeas not exist, version-specific folder"
			}
		}
	}
	WriteMessage -success "$modName has correct folder structure"
}

# Jumps to a mod-folder
function Get-LocalModFolder {
	param($modName)

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
	param([switch]$Test)
	$currentDirectory = (Get-Location).Path
	if (-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
		WriteMessage -failure "Can only be run from somewhere under $localModFolder, exiting"
		return			
	}
	$files = Get-ChildItem *.xml -Recurse
	$replacements = Get-Content $replacementsFile -Encoding UTF8
	$infoBlob = ""
	foreach ($file in $files) {
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
	if ($infoBlob -ne "") {
		Write-Host $infoBlob.Replace("#n", "`n")
	}
}


# XML-cleaning function
# Resaves all XML-files using validated XML. Also warns if there seems to be overwritten base-defs
# Useful to run on a mod to remove all extra whitespaces and redundant formatting
function Set-ModXml {
	param([switch]$skipBaseCheck,
		$modName,
		[switch]$currentDir)
	$currentDirectory = (Get-Location).Path
	if ($currentDir) {
		if (-not $currentDirectory.StartsWith($localModFolder)) {
			WriteMessage -failure "Can only be run from somewhere under $localModFolder, exiting"
			return
		}
		$modFolder = $currentDirectory
	} else {
		if (-not $modName) {
			if (-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
				WriteMessage -failure "Can only be run from somewhere under $localModFolder, exiting"
				return			
			}
			$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
		}	
		$modFolder = "$localModFolder\$modName"		
	}
	
	# Clean up XML-files
	$files = Get-ChildItem "$modFolder\*.xml" -Recurse
	foreach ($file in $files) {
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
			continue
		}
		if ($skipBaseCheck) {
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
		$fileContent.Save($file.FullName)
	}
}


# Generates a zip-file of a mod, looking in the _PublisherPlus.xml for exlusions
function Get-ZipFile {
	param([string]$modname,
		[string]$filename)
	$exclusionFile = "$localModFolder\$modname\_PublisherPlus.xml"
	$exclusionsToAdd = " -xr!""_PublisherPlus.xml"""
	if (Test-Path $exclusionFile) {
		foreach ($exclusion in ([xml](Get-Content $exclusionFile -Raw -Encoding UTF8)).Configuration.Excluded.exclude) {
			$niceExclusion = $exclusion.Replace("$localModFolder\$modname\", "")
			$exclusionsToAdd += " -xr!""$niceExclusion"""
		}
	}
	$outFile = "$localModFolder\$modname\$filename"
	$7zipPath = $settings.zip_path
	$arguments = "a ""$outFile"" ""$localModFolder\$modname\"" -r -mx=9 -mmt=10 -bd $exclusionsToAdd "
	Start-Process -FilePath $7zipPath -ArgumentList $arguments -Wait -NoNewWindow
}

# Gets the about-file from a mod
function Get-ModAboutFile {
	param(
		$modName,
		[switch]$xml
	)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}
	
	$modFolder = "$localModFolder\$modName"
	$aboutFilePath = "$modFolder\About\About.xml"
	if (-not (Test-Path $aboutFilePath)) {
		WriteMessage -warning "No about-file for $modName"
		return
	}

	if ($xml) {
		return [xml](Get-Content $aboutFilePath -Raw -Encoding UTF8)
	}
	
	return (Get-Content $aboutFilePath -Raw -Encoding UTF8)
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

	if (-not (Get-HtmlPageStuff -url "https://steamcommunity.com/sharedfiles/filedetails/?id=$modId" -subscribers)) {
		WriteMessage -failure "https://steamcommunity.com/sharedfiles/filedetails/?id=$modId is not working"
		return $false
	}
	
	$modContentPath = "$localModFolder\..\..\..\workshop\content\294100\$modId"
	$subscribed = Test-Path "$modContentPath\About\About.xml"
	if (-not $subscribed) {
		Set-ModSubscription -modId $modId -subscribe $true	
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
		Set-ModSubscription -modId $modId -subscribe $false	
	}

	return $true
}

#endregion

#region Get-info functions

# Easy load of a mods steam-page
# Gets the published ID for a mod and then opens it in the selected browser
function Get-ModPage {
	param(
		[string]$modName,
		[switch]$getLink
	)
	if (-not $modName) {
		$currentDirectory = (Get-Location).Path
		if (-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
			WriteMessage -failure "Can only be run from somewhere under $localModFolder, exiting"
			return			
		}
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
	}
	$modFileId = "$localModFolder\$modName\About\PublishedFileId.txt"
	if (-not (Test-Path $modFileId)) {
		WriteMessage -failure "No id found for mod at $modFileId, exiting."
		return
	}
	$modId = Get-Content $modFileId -Raw -Encoding UTF8
	$arguments = "https://steamcommunity.com/sharedfiles/filedetails/?id=$modId"
	if ($getLink) {
		return $arguments
	}
	$applicationPath = $settings.browser_path
	Start-Process -FilePath $applicationPath -ArgumentList $arguments
	Start-Sleep -Seconds 1
	Remove-Item "$localModFolder\$modName\debug.log" -Force -ErrorAction SilentlyContinue
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

# Fetchs a mods subscriber-number
function Get-ModSubscribers {
	param(
		$modName,
		$modLink
	)
	if (-not $modLink) {
		if (-not $modName) {
			$modName = Get-CurrentModNameFromLocation
			if (-not $modName) {
				return
			}
		}
		$modFileId = "$localModFolder\$modName\About\PublishedFileId.txt"
		if (-not (Test-Path $modFileId)) {
			WriteMessage -failure "$modFileId not found, exiting"
			return
		}
		$modId = Get-Content $modFileId -Raw -Encoding UTF8
		$url = "https://steamcommunity.com/sharedfiles/filedetails/?id=$modId"
	} else {
		$url = $modLink
	}
	return Get-HtmlPageStuff -url $url -subscribers
}

# Fetchs a mods supported versions
function Get-ModVersions {
	param(
		$modName,
		$modLink,
		[switch] $local
	)
	if ($local) {
		if (-not $modName) {
			$modName = Get-CurrentModNameFromLocation
			if (-not $modName) {
				return
			}
		}
		return Get-ModVersionFromAboutFile -aboutFilePath "$localModFolder\$modName\About\About.xml"		
	}

	if (-not $modLink) {
		if (-not $modName) {
			$modName = Get-CurrentModNameFromLocation
			if (-not $modName) {
				return
			}
		}
		$modFileId = "$localModFolder\$modName\About\PublishedFileId.txt"
		if (-not (Test-Path $modFileId)) {
			WriteMessage -failure "$modFileId not found, exiting"
			return
		}
		$modId = Get-Content $modFileId -Raw -Encoding UTF8
		$url = "https://steamcommunity.com/sharedfiles/filedetails/?id=$modId"
	} else {
		$url = $modLink
	}
	return Get-HtmlPageStuff -url $url
}

# Gets the versions supported in the about-file
function Get-ModVersionFromAboutFile {
	param(
		$aboutFilePath
	)
	if ($aboutFilePath -notmatch "About.xml") {
		WriteMessage -failure "$aboutFilePath is not a Rimworld about-file, exiting"
		return
	}
	if (-not (Test-Path $aboutFilePath)) {
		WriteMessage -failure "No aboutfile found at path $aboutFilePath"
		return
	}
	$aboutContent = [xml](Get-Content $aboutFilePath -Raw -Encoding UTF8)
	if ($aboutContent.ModMetaData.author) {
		return $aboutContent.ModMetaData.supportedVersions.li
	}
	return @()
}

# Gets the author of a mod from the About-file
function Get-ModAuthorFromAboutFile {
	param(
		$aboutFilePath
	)
	if ($aboutFilePath -notmatch "About.xml") {
		WriteMessage -failure "$aboutFilePath is not a Rimworld about-file, exiting"
		return
	}
	if (-not (Test-Path $aboutFilePath)) {
		WriteMessage -failure "No aboutfile found at path $aboutFilePath"
		return
	}
	$aboutContent = [xml](Get-Content $aboutFilePath -Raw -Encoding UTF8)
	return $aboutContent.ModMetaData.author
}

# Returns true if the mod supports the latest game-version
function Get-ModSteamStatus {
	[CmdletBinding()]
	param (
		$modName,
		$modLink
	)
	$currentVersionString = Get-CurrentRimworldVersion
	if ($modLink) {
		$modVersions = Get-ModVersions -modLink $modLink
	}
	if ($modName) {		
		$modVersions = Get-ModVersions -modName $modName
	}
	if (-not $modVersions) {
		Write-Verbose "Can not find mod on Steam. Modname: $modName, ModLink: $modLink, exiting"
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
	param ([string]$author,
		[switch]$onlyPublished)
	$allMods = Get-ChildItem -Directory $localModFolder
	$returnArray = @()
	foreach ($folder in $allMods) {
		if (-not (Test-Path "$($folder.FullName)\About\About.xml")) {
			continue
		}
		if ($onlyPublished -and -not (Test-Path "$($folder.FullName)\About\PublishedFileId.txt")) {
			continue
		}
		$aboutFile = "$($folder.FullName)\About\About.xml"
		if ((Get-ModAuthorFromAboutFile -aboutFilePath $aboutFile) -eq $author) {
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
	foreach ($folder in $allMods) {
		if (-not (Test-Path "$($folder.FullName)\About\ModSync.xml")) {
			continue
		}
		if (-not (Test-Path "$($folder.FullName)\About\PublishedFileId.txt")) {
			continue
		}
		$modsyncFileModified = (Get-Item "$($folder.FullName)\About\ModSync.xml").LastWriteTime

		if ($ignoreAbout) {
			$newerFiles = Get-ChildItem $folder.FullName -File -Recurse -Exclude "About.xml" | Where-Object { $_.LastWriteTime -gt $modsyncFileModified.AddMinutes(5) }
		} else {
			$newerFiles = Get-ChildItem $folder.FullName -File -Recurse  | Where-Object { $_.LastWriteTime -gt $modsyncFileModified.AddMinutes(5) }
		}
		if ($newerFiles.Count -gt 0) {
			$returnString = "`n$($folder.Name) has $($newerFiles.Count) files newer than publish-date"
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
	return $returnArray
}

# Scans a mods About-file for mod-identifiers and returns an array of them, with the selected mods identifier last
function Get-IdentifiersFromMod {
	param ([string]$modname,
		[string]$modId,
		[switch]$oldmod, 
		[switch]$alsoLoadBefore,
		[string]$modFolderPath,
		[string]$gameVersion,
		[switch]$bare)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}
	if ($modId) {
		if (-not (Test-Path "$localModFolder\..\..\..\workshop\content\294100\$modId")) {
			WriteMessage -progress "Could not find mod with id $modId, subscribing"
			Set-ModSubscription -modId $modId -subscribe $true
			Update-IdentifierToFolderCache
		}
		$aboutFile = "$localModFolder\..\..\..\workshop\content\294100\$modId\About\About.xml"
	} else {
		if ($modFolderPath) {		
			$aboutFile = "$modFolderPath\About\About.xml"
		} else {
			$aboutFile = "$localModFolder\$modname\About\About.xml"		
		}
	}
	if (-not (Test-Path $aboutFile)) {
		WriteMessage -failure "Could not find About-file for mod named $modname $modId"
		return @()
	}
	if (-not $gameVersion) {
		$gameVersion = Get-CurrentRimworldVersion
	}
	$aboutFileContent = [xml](Get-Content $aboutFile -Raw -Encoding UTF8)
	$identifiersToAdd = @()
	if ($oldmod) {
		$identifiersToAdd += $modName
		return $identifiersToAdd
	}
	if ($identifierCache.Count -eq 0) {
		Update-IdentifierToFolderCache
	}
	$identifiersToIgnore = "brrainz.harmony", "unlimitedhugs.hugslib", "ludeon.rimworld", "ludeon.rimworld.royalty", "ludeon.rimworld.ideology", "ludeon.rimworld.biotech", "mlie.showmeyourhands"
	if ($bare) {
		$identifiersToIgnore = "brrainz.harmony", "ludeon.rimworld", "ludeon.rimworld.royalty", "ludeon.rimworld.ideology", "ludeon.rimworld.biotech"
	}
	foreach ($identifier in $aboutFileContent.ModMetaData.modDependencies.li.packageId) {
		if (-not ($identifier.Contains(".")) -or $identifiersToIgnore.Contains($identifier.ToLower()) -or $identifier.Contains(" ")) {
			continue
		}
		foreach ($subIdentifier in (Get-IdentifiersFromSubMod $identifierCache[$identifier])) {
			if ($identifiersToAdd -notcontains $subIdentifier.ToLower()) {
				$identifiersToAdd += $subIdentifier.ToLower()
			}
		}
		if ($identifiersToAdd -notcontains $identifier.ToLower()) {
			$identifiersToAdd += $identifier.ToLower()
		}
	}
	if ($aboutFileContent.ModMetaData.modDependenciesByVersion) {
		foreach ($identifier in $aboutFileContent.ModMetaData.modDependenciesByVersion."v$gameVersion".li.packageId) {
			if (-not ($identifier.Contains(".")) -or $identifiersToIgnore.Contains($identifier.ToLower()) -or $identifier.Contains(" ")) {
				continue
			}
			foreach ($subIdentifier in (Get-IdentifiersFromSubMod $identifierCache[$identifier])) {
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
		foreach ($identifier in $aboutFileContent.ModMetaData.loadAfter.li) {
			if (-not ($identifier.Contains(".")) -or $identifiersToIgnore.Contains($identifier.ToLower()) -or $identifier.Contains(" ")) {
				continue
			}
			if (-not $identifiersToAdd.Contains($identifier.ToLower())) {
				$identifiersToAdd += $identifier.ToLower()
			}
		}
	}
	$identifiersToAdd += $aboutFileContent.ModMetaData.packageId.ToLower()
	return $identifiersToAdd
}

# Fetches identifiers from a mod-requirement mod
function Get-IdentifiersFromSubMod {
	param (
		$modFolderPath,
		[switch]$dontIgnore
	)
	if (-not $modFolderPath) {
		$modFolderPath = (Get-Location).Path
	}

	$aboutFile = "$modFolderPath\About\About.xml"
	if (-not (Test-Path $aboutFile)) {
		WriteMessage -warning "Could not find About-file for mod in $modFolderPath"
		return @()
	}
	$aboutFileContent = [xml](Get-Content $aboutFile -Raw -Encoding UTF8)
	$identifiersToIgnore = "brrainz.harmony", "unlimitedhugs.hugslib", "ludeon.rimworld", "ludeon.rimworld.royalty", "mlie.showmeyourhands"
	if ($dontIgnore) {
		$identifiersToIgnore = @()
	}
	$identifiersToReturn = @()
	foreach ($identifier in $aboutFileContent.ModMetaData.modDependencies.li.packageId) {
		if (-not ($identifier.Contains(".")) -or $identifiersToIgnore.Contains($identifier.ToLower()) -or $identifier.Contains(" ")) {
			continue
		}
		$identifiersToReturn += $identifier.ToLower()
	}
	if ($aboutFileContent.ModMetaData.modDependenciesByVersion) {
		foreach ($identifier in $aboutFileContent.ModMetaData.modDependenciesByVersion."v$gameVersion".li.packageId) {
			if (-not ($identifier.Contains(".")) -or $identifiersToIgnore.Contains($identifier.ToLower()) -or $identifier.Contains(" ")) {
				continue
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
	$total = 0
	foreach ($folder in $allMods) {
		$modName = $folder.Name
		$modFileId = "$($folder.FullName)\About\PublishedFileId.txt"
		if (-not (Test-Path $modFileId)) {
			continue
		}
		if (-not (Get-OwnerIsMeStatus -modName $modName)) {
			continue
		}
		if ($NoVs) {
			$cscprojFiles = Get-ChildItem -Recurse -Path $folder.FullName -Include *.csproj
			if ($cscprojFiles.Length -gt 0) {
				continue
			}
		}
		if ($NoDependencies -and (Get-IdentifiersFromMod -modname $folder.Name).Count -gt 1) {
			continue
		}
		$total++
	}
	return $total
}

# Gets the highest version for a mod dependency
function Get-ModDependencyMaxVersion {
	[CmdletBinding()]
	param($modName,
		[switch]$supportsLatest)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			if ($supportsLatest) {
				return $false
			}
			return
		}
	}
	if (-not (Get-OwnerIsMeStatus -modName $modName)) {
		WriteMessage -failure "$modName is not mine, aborting update"
		if ($supportsLatest) {
			return $false
		}
		return
	}
	if ($identifierCache.Count -eq 0) {
		Update-IdentifierToFolderCache
	}
	$identifiers = Get-IdentifiersFromMod -modname $modName

	if ($identifiers.Count -le 1) {
		WriteMessage -progress "$modName has no dependecies, exiting"
		if ($supportsLatest) {
			return $true
		}
		return
	}

	$maxVersion = [version]"0.0"
	foreach ($identifier in $identifiers) {
		if ($identifier -match "$modName") {
			continue
		}
		$modPath = $identifierCache[$identifier]
		if (-not $modPath) {
			WriteMessage -warning "Could not find the mod for identifier $identifier"
			continue
		}
		if (-not (Test-Path $modPath)) {
			WriteMessage -warning "Could not find the folder for $identifier at $modPath"
			continue
		}
		$supportedVersions = Get-ModVersionFromAboutFile -aboutFilePath "$modPath\About\About.xml"
		if (-not $supportedVersions) {
			WriteMessage -warning "Could not find any supported versions in about file for $identifier at $modPath"
			continue
		}
		if ($supportedVersions.Count -eq 1) {
			$currentMax = $supportedVersions	
		} else {
			$currentMax = $supportedVersions[-1]
		}
		WriteMessage -progress  "$identifier supports $currentMax"
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
	if ($identifierCache.Lenght -eq 0) {		
		Update-IdentifierToFolderCache
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
			if ($identifierCache.Contains("$identifier")) {
				$allMods += Get-Item $identifierCache["$identifier"]
			}
		}
	} else {		
		$allMods = Get-ChildItem -Directory $localModFolder
	}
	$allMatchingFiles = @()
	$i = 0
	$total = $allMods.Count
	$filterPart = "*.xml"
	if ($alsoCs) {		
		$filterPart = ('*.xml', '*.cs')
	}
	foreach ($job in Get-Job) {
		Stop-Job $job | Out-Null
		Remove-Job $job | Out-Null
	}
	foreach ($folder in ($allMods | Get-Random -Count $total)) {
		$i++
		$percent = [math]::Round($i / $total * 100)
		Write-Progress -Activity "$($allMatchingFiles.Count) matches found, looking in $($folder.name), " -Status "$i of $total" -PercentComplete $percent;
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
				$result
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
	foreach ($job in Get-Job -State Completed) {
		$result = Receive-Job $job
		$allMatchingFiles += $result		
		if (-not $finalOutput) {
			$result
		}
		Remove-Job $job | Out-Null
	}
	foreach ($job in Get-Job -State Blocked) {
		WriteMessage -failure "$($job.Name) failed to exit, stopping it."
		Stop-Job $job | Out-Null
		Remove-Job $job | Out-Null
	}
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

# Checks if I am the owner of the mod
function Get-OwnerIsMeStatus {
	param($modName)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}

	$modFolder = "$localModFolder\$modName"
	if (-not (Test-Path $modFolder)) {
		WriteMessage -failure "$modFolder can not be found, exiting"
		return $false
	}
	$aboutFile = "$modFolder\About\About.xml"
	if (-not (Test-Path $aboutFile)) {
		WriteMessage -failure "$aboutFile can not be found, exiting"
		return $false
	}

	$aboutContent = Get-ModAboutFile -modName $modName -xml
	if (-not $aboutContent.ModMetaData.packageId) {
		return $false
	}
	return $aboutContent.ModMetaData.packageId.StartsWith($settings.mod_identifier_prefix)
}

# Finds all mods that is dependent on a mod
function Get-NextModDependancy {
	param($modId,
		$modName,
		[switch]$alsoBefore,
		[switch]$test)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation		
	}
	if ($modName) {
		$folders = Get-ChildItem $localModFolder -Directory | Where-Object { $_.Name -gt $modName }
	} else {
		$folders = Get-ChildItem $localModFolder -Directory
	}
	foreach ($folder in $folders) {
		$identifiers = Get-IdentifiersFromMod -modname $folder.Name -alsoLoadBefore:$alsoBefore
		if ($identifiers.Contains($modId.ToLower())) {
			Set-Location $folder.FullName
			WriteMessage -progress "Found $modId in mod $($folder.Name)"
			if ($test) {
				Test-Mod
			}
			return
		}
	}
	WriteMessage -warning "$modId not found."
}

function Get-NextModFolder {
	$allMods = Get-ChildItem -Directory $localModFolder
	$currentFolder = (Get-Location).Path
	$foundStart = $currentFolder -eq $localModFolder
	$counter = $allMods.Count
	foreach ($folder in $allMods) {
		if (-not $foundStart) {
			if ($folder.FullName -eq $currentFolder) {
				$foundStart = $true
			}
			$counter--
			continue
		}
		WriteMessage -progress "$counter of $($allMods.Count)"
		Set-Location $folder.FullName
		return
	}
	WriteMessage -warning "Already standing on the last mod-folder"
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
		[switch]$TotalOnly,
		$ModsToIgnore,
		[int]$MaxToFetch = -1,
		[switch]$RandomOrder)
	$currentVersionString = Get-CurrentRimworldVersion
	$allMods = Get-ChildItem -Directory $localModFolder
	if ($RandomOrder) {
		$allMods = $allMods | Sort-Object { Get-Random }
	}
	if ($MaxToFetch -eq 0) {
		$MaxToFetch = $allMods.Length
	}
	if (-not $ModsToIgnore) {
		$ModsToIgnore = @()
	}
	$currentFolder = (Get-Location).Path
	if ($currentFolder -eq $localModFolder -and $NextOnly) {
		$NextOnly = $false
		$FirstOnly = $true
		WriteMessage -warning "Standing in root-dir, will assume FirstOnly instead of NextOnly"
	}
	$foundStart = $false
	$counter = 0
	foreach ($folder in $allMods) {
		if ($NextOnly -and (-not $foundStart)) {
			if ($folder.FullName -eq $currentFolder) {				
				WriteMessage -progress "Will search for next mod from $currentFolder"
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
		if (-not (Test-Path "$($folder.FullName)\About\PublishedFileId.txt")) {
			continue
		}
		if (-not (Get-OwnerIsMeStatus -modName $folder.Name)) {
			continue
		}
		if (-not $IgnoreLastErrors -and (Test-Path "$($folder.FullName)Source\lastrun.log")) {
			continue
		}
		if ($NoVs) {
			$cscprojFiles = Get-ChildItem -Recurse -Path $folder.FullName -Include *.csproj
			if ($cscprojFiles.Length -gt 0) {
				continue
			}
		}
		$aboutFile = "$($folder.FullName)\About\About.xml"
		if ($NoDependencies -and (Get-IdentifiersFromMod -modname $folder.Name -bare).Count -gt 1) {
			continue
		}

		if (-not $NotFinished -and (Get-ModVersionFromAboutFile -aboutFilePath $aboutFile).Contains($currentVersionString)) {
			continue
		}

		if ($NotFinished) {
			if ((Get-Item "$($folder.FullName)\About\Changelog.txt").LastWriteTime -ge (Get-Item $aboutFile).LastWriteTime.AddMinutes(-5)) {
				continue
			}
			if (-not (Get-ModVersionFromAboutFile -aboutFilePath $aboutFile).Contains($currentVersionString)) {
				continue
			}
		}

		if ($TotalOnly) {
			$counter++
			continue
		}

		if ($FirstOnly -or $NextOnly) {
			Set-Location $folder.FullName
			return $true
		}
		Write-Host $folder.Name
		$counter++
	}
	if ($TotalOnly) {
		return $counter
	}
}

# Looks for all files that is not supposed to be there
function Get-NonValidFilesFromMod {
	param($modName)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}
	$modFolder = "$localModFolder\$modName"
	if (-not (Test-Path $modFolder)) {
		Write-Host "$modFolder can not be found, exiting"
		return $false
	}
	
	$nonGraphicFiles = Get-ChildItem -Exclude *.png, *.jpg -File -Recurse -Path "$modFolder\Textures"
	$nonXmlFiles = Get-ChildItem -Exclude Textures, Source, Assemblies, Sounds, News -Directory -Path "$modFolder" | Get-ChildItem -Exclude *.xml, Preview.png,Changelog.txt,PublishedFileId.txt  -File | Where-Object { $_.FullName -notmatch "Assemblies" }

	if ($nonGraphicFiles) {
		Write-Host -ForegroundColor Yellow "Found $($nonGraphicFiles.Count) non-graphic files in Texture-folder"
		Write-Host ($nonGraphicFiles -join "`n")
	}
	if ($nonXmlFiles) {
		Write-Host -ForegroundColor Yellow "Found $($nonXmlFiles.Count) non-xml files in the data-folders"
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
	param([switch]$versionObject)
	$rimworldVersionFile = "$localModFolder\..\Version.txt"
	$currentRimworldVersion = [version]([regex]::Match((Get-Content $rimworldVersionFile -Raw -Encoding UTF8), "[0-9]+\.[0-9]+")).Value
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

# Helper function to scrape page
function Get-HtmlPageStuff {
	[CmdletBinding()]
	param (
		$url,
		$cacheTime = 30,
		[switch] $previewUrl,
		[switch] $subscribers,
		[switch] $visibility,
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
		if ($html.InnerText -match "An error was encountered while processing your request:") {
			return
		}
		if ($visibility) {
			if ($html.InnerText -match "Current visibility: Unlisted") {
				return "Unlisted"
			}
			if ($html.InnerText -match "Current visibility: Hidden") {
				return "Hidden"
			}
			if ($html.InnerText -match "Current visibility: Friends-only") {
				return "Friends"
			}
			return "Public"
		}
		if ($subscribers) {
			return $html.SelectNodes("//table").SelectNodes("//td")[2].InnerText.Replace(",", "")
		}
		if ($previewUrl) {
			$imgSrc = $html.SelectNodes("//img[contains(@id, 'previewImageMain')]").GetAttributeValue("src", "")
			if (-not $imgSrc) {
				$imgSrc = $html.SelectNodes("//img[contains(@id, 'previewImage')]").GetAttributeValue("src", "")
			}
			if ($imgSrc) {
				return "$($imgSrc.Split("?")[0])"
			}
			return
		}
		if ($previewSavePath) {
			if (-not (Test-Path $previewSavePath)) {
				WriteMessage -warning "$previewSavePath does not exist, will not download preview images"
				return
			}
			$previewNodes = $html.SelectNodes("//div[@class='highlight_strip_item highlight_strip_screenshot']")
			if (-not $previewNodes) {
				WriteMessage -progress  "No preview images found, ignoring"
				return
			}
			$counter = 0
			WriteMessage -progress  "Trying to download $($previewNodes.Count) preview images"
			$total = $previewNodes.Count

			for ($i = 1; $i -le $previewNodes.Count; $i++) {	
				$percent = [math]::Round($i / $total * 100)
				Write-Progress -Activity "Downloading preview-image $i" -Status "$i of $total" -PercentComplete $percent
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
			WriteMessage -success "Saved $counter preview-images to $previewSavePath"
			return
		}
		$versionsHtml = $html.SelectNodes("//div[contains(@class, 'rightDetailsBlock')]")[0].InnerText.Trim()
		$versions = $versionsHtml.Replace(" ", "").Split(",")
		return $versions | Where-Object { $_ -and $_ -ne "Mod" }		
	} catch {
		WriteMessage -warning  "Failed to fetch data from $url `n$($_.ScriptStackTrace)`n$_"
	}
}


function Get-NextVersionNumber {
	param (
		[version]$currentVersion
	)
	$currentRimworldVersion = Get-CurrentRimworldVersion -versionObject

	if ($currentVersion.Major -ne $currentRimworldVersion.Major) {
		return [version]"$($currentRimworldVersion.Major).$($currentRimworldVersion.Minor).1"
	}
	if ($currentVersion.Minor -ne $currentRimworldVersion.Minor) {
		return [version]"$($currentRimworldVersion.Major).$($currentRimworldVersion.Minor).1"
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
	}
	[int]$answer = Read-Host "Select matching or empty for exit"
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


# Caches all mod-identifiers for quick referencing
function Update-IdentifierToFolderCache {
	# First steam-dirs
	WriteMessage -progress  "Caching identifiers"
	Get-ChildItem "$localModFolder\..\..\..\workshop\content\294100" -Directory | ForEach-Object {
		$continue = Test-Path "$($_.FullName)\About\About.xml"
		if (-not $continue) {			
			Write-Verbose "Ignoring $($_.Name) - No aboutfile"
		} else {
			$continue = Test-Path "$($_.FullName)\About\PublishedFileId.txt"
			if (-not $continue) {			
				Write-Verbose "Ignoring $($_.Name) - Not published"
			} else {
				$aboutContent = [xml](Get-Content -path "$($_.FullName)\About\About.xml" -Raw -Encoding UTF8)
				if (-not ($aboutContent.ModMetaData.packageId)) {
					Write-Verbose "Ignoring $($_.Name) - No identifier"
				} else {
					$identifierCache["$($aboutContent.ModMetaData.packageId.ToLower())"] = $_.FullName						
				}			
			}
		}		
	}
	# Then the local mods
	Get-ChildItem $localModFolder -Directory | ForEach-Object {  		
		$continue = Test-Path "$($_.FullName)\About\About.xml"
		if (-not $continue) {			
			Write-Verbose "Ignoring $($_.Name) - No aboutfile"
		} else {
			$continue = Test-Path "$($_.FullName)\About\PublishedFileId.txt"
			if (-not $continue) {			
				Write-Verbose "Ignoring $($_.Name) - Not published"
			} else {
				$aboutContent = [xml](Get-Content -path "$($_.FullName)\About\About.xml" -Raw -Encoding UTF8)
				if (-not ($aboutContent.ModMetaData.packageId)) {
					Write-Verbose "Ignoring $($_.Name) - No identifier"
				} else {
					$identifierCache["$($aboutContent.ModMetaData.packageId.ToLower())"] = $_.FullName						
				}			
			}
		}	
	}
	WriteMessage -success "Done, cached $($identifierCache.Count) mod identifiers"
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
			$answer = Read-Host "Select save to start or empty to list five more"
			if ($answer -and (([int]$counter - 5)..[int]$counter) -contains $answer) {
				$selectedSave = $allSaves[$answer - 1]
				Write-Host "Selected $($selectedSave.BaseName)"
				$modFileXml = [xml](Get-Content $modFile -Encoding UTF8)
				$saveFileXml = [xml](Get-Content $selectedSave.FullName -Encoding UTF8)
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

function Set-RimworldRunMode {
	param (
		$prefsFile = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\Prefs.xml",
		[switch]$testing
	)
	if (-not (Test-Path $prefsFile)) {
		WriteMessage -failure "Found no prefs-file at $prefsFile"
		return
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
	} else {
		$prefsContent = $prefsContent.Replace("<devMode>True</devMode>", "<devMode>False</devMode>")
		$prefsContent = $prefsContent.Replace("<volumeMusic>$($settings.modding_music_volume)</volumeMusic>", "<volumeMusic>$($settings.playing_music_volume)</volumeMusic>")
		$prefsContent = $prefsContent.Replace("<screenWidth>$($settings.modding_screen_witdh)</screenWidth>", "<screenWidth>$($settings.playing_screen_witdh)</screenWidth>")
		$prefsContent = $prefsContent.Replace("<screenHeight>$($settings.modding_screen_height)</screenHeight>", "<screenHeight>$($settings.playing_screen_height)</screenHeight>")
		$prefsContent = $prefsContent.Replace("<fullscreen>False</fullscreen>", "<fullscreen>True</fullscreen>")
		$prefsContent = $prefsContent.Replace("<testMapSizes>True</testMapSizes>", "<testMapSizes>False</testMapSizes>")
	}
	$prefsContent | Set-Content $prefsFile -Encoding utf8
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
	param ([switch]$play,
		[string]$testMod,
		[string]$testAuthor,
		[switch]$alsoLoadBefore,
		[switch]$rimThreaded,
		[Parameter()][ValidateSet('1.0', '1.1', '1.2', '1.3', 'latest')][string[]]$version,
		$otherModid,
		$mlieMod,
		[switch]$autotest,
		[switch]$force,
		[switch]$bare
	)

	if ($test -and $play) {
		WriteMessage -failure "You cant test and play at the same time."
		return
	}
	if (-not $oldRimworldFolder -and $version -eq "latest") {
		WriteMessage -failure "No old RimWorld-folder defined, cannot start old version."
		return		
	}
	if ($version -and -not ($play -or $testMod)) {
		WriteMessage -failure "Only testing or playing is supported for old versions of RimWorld"
		return		
	}

	$prefsFile = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\Prefs.xml"
	$modFile = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\Config\ModsConfig.xml"
	if ($version -and $version -ne "latest") {
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
		if ($autotest -or $bare) {
			Copy-Item $autoModsConfig $modFile -Confirm:$false
		}	
		$modsToTest = Get-AllModsFromAuthor -author $testAuthor -onlyPublished
		$modIdentifiersPrereq = ""
		$modIdentifiers = ""
		foreach ($modname in $modsToTest) {
			if ($alsoLoadBefore) {
				$identifiersToAdd = Get-IdentifiersFromMod -modname $modname -alsoLoadBefore
			} else {
				$identifiersToAdd = Get-IdentifiersFromMod -modname $modname			
			}
			if ($identifiersToAdd.Length -eq 0) {
				WriteMessage -failure "No mod identifiers found, exiting."
				return
			}
			if ($identifiersToAdd.Count -eq 1) {
				WriteMessage -progress "Adding $identifiersToAdd as mod to test"
				$modIdentifiers += "<li>$identifiersToAdd</li>"
			} else {
				foreach ($identifier in $identifiersToAdd) {
					if ($modIdentifiersPrereq.Contains($identifier) -or $modIdentifiers.Contains($identifier) ) {
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
		(Get-Content $modFile -Raw -Encoding UTF8).Replace("</activeMods>", "$modIdentifiersPrereq</activeMods>").Replace("</activeMods>", "$modIdentifiers</activeMods>") | Set-Content $modFile
		Set-RimworldRunMode -prefsFile $prefsFile -testing
	}
	if ($testMod) {
		if ((-not $force) -and (-not (Get-OwnerIsMeStatus -modName $testMod))) {
			WriteMessage -failure "Not my mod, exiting."
			return
		}
		if ($version -and $version -ne "latest") {			
			Copy-Item $testModFile $modFile -Confirm:$false
			if ($version -eq "1.0") {
				$identifiersToAdd = Get-IdentifiersFromMod -modname $testMod -oldmod
			} else {
				if ($alsoLoadBefore) {
					$identifiersToAdd = Get-IdentifiersFromMod -modname $modname -gameVersion $version -alsoLoadBefore
				} else {
					$identifiersToAdd = Get-IdentifiersFromMod -modname $modname -gameVersion $version		
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
					Remove-Item -Path "$oldModFolder\$mlieModFolder" -Recurse -Force
				}
				Copy-Item -Path "$localModFolder\$mlieModFolder" -Destination "$oldModFolder\" -Confirm:$false -Recurse -Force
			}
			if (Test-Path "$oldModFolder\$modname") {
				Remove-Item -Path "$oldModFolder\$modname" -Recurse -Force
			}
			Copy-Item -Path "$localModFolder\$modname" -Destination "$oldModFolder\" -Confirm:$false -Recurse -Force
			if (Test-Path "$localModFolder\$modname\_PublisherPlus.xml") {
				(Get-Content "$localModFolder\$modname\_PublisherPlus.xml" -Raw -Encoding UTF8).Replace($localModFolder, $oldModFolder) | Set-Content "$oldModFolder\$modname\_PublisherPlus.xml" -Encoding UTF8
			}
		} else {
			Copy-Item $testingModsConfig $modFile -Confirm:$false	
			if ($autotest -or $bare) {
				Copy-Item $autoModsConfig $modFile -Confirm:$false
			}	
			if ($alsoLoadBefore) {
				$identifiersToAdd = Get-IdentifiersFromMod -modname $modname -alsoLoadBefore
			} else {
				$identifiersToAdd = Get-IdentifiersFromMod -modname $modname			
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
		# if($identifiersToAdd.Length -eq 0) {
		# 	WriteMessage -failure "No mod identifiers found, exiting."
		# 	return
		# }
		$modIdentifiers = ""
		if ($autotest) {
			$modIdentifiers += "<li>mlie.autotester</li>"
		}
		if ($bare) {
			$modIdentifiers += "<li>taranchuk.moderrorchecker</li>"
		}
		if ($mlieMod) {
			$modIdentifiers += "<li>$($mlieMod.ToLower())</li>"
		}
		if ($identifiersToAdd.Count -eq 1) {
			WriteMessage -progress "Adding $identifiersToAdd as mod to test"
			$modIdentifiers += "<li>$identifiersToAdd</li>"
		} else {			
			foreach ($identifier in $identifiersToAdd) {
				if ($identifier -eq $identifiersToAdd[$identifiersToAdd.Length - 1]) {
					WriteMessage -progress "Adding $identifier as mod to test"
				} else {
					WriteMessage -progress "Adding $identifier as prerequirement"
				}
				$modIdentifiers += "<li>$identifier</li>"
			}	
		}
		if ($rimThreaded) {
			WriteMessage -progress "Adding RimThreaded last"
			$modIdentifiers += "<li>majorhoff.rimthreaded</li>"
		}
		(Get-Content $modFile -Raw -Encoding UTF8).Replace("</activeMods>", "$modIdentifiers</activeMods>") | Set-Content $modFile
		Set-RimworldRunMode -prefsFile $prefsFile -testing
	}
	if ($play) {
		if (-not $version -or $version -eq "latest") {	
			Copy-Item $playingModsConfig $modFile -Confirm:$false
		}		
		Set-RimworldRunMode -prefsFile $prefsFile
	}
	if (-not $testMod -and -not $play -and -not $testAuthor ) {
		Copy-Item $moddingModsConfig $modFile -Confirm:$false
		Set-RimworldRunMode -prefsFile $prefsFile -testing
	}
	# if (-not $version -or $version -eq "latest") {
	# 	$hugsSettingsPath = "$env:LOCALAPPDATA\..\LocalLow\Ludeon Studios\RimWorld by Ludeon Studios\HugsLib\ModSettings.xml"
	# 	$hugsContent = Get-Content $hugsSettingsPath -Encoding UTF8 -Raw
	# 	if ($autotest) {
	# 		$hugsContent.Replace("Disabled", "GenerateMap") | Out-File $hugsSettingsPath -Encoding utf8
	# 	} else {
	# 		$hugsContent.Replace("GenerateMap", "Disabled") | Out-File $hugsSettingsPath -Encoding utf8
	# 	}
	# }

	Start-Sleep -Seconds 2
	$currentLocation = Get-Location
	if ($version -and $version -ne "latest") {	
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
		
		if (-not ((Get-Item -Path $logPath).LastWriteTime -ge (Get-Date).AddSeconds(-30))) {
			break
		}

		if (-not (Get-Process -Name "RimWorldWin64" -ErrorAction SilentlyContinue)) {
			break
		}
		Start-Sleep -Seconds 1
	}
	Stop-RimWorld
	$logContent = Get-Content $logPath -Raw -Encoding UTF8
	$errors = $logContent.Contains("[ERROR]") -or $logContent.Contains("[WARNING]")
	if ($errors) {
		Copy-Item $logPath "$localModFolder\$modname\Source\lastrun.log" -Force | Out-Null
	}
	return (-not $errors)
}

# Test the mod in the current directory
function Test-Mod {
	param([Parameter()]
		[ValidateSet('1.0', '1.1', '1.2', '1.3', 'latest')]
		[string[]]
		$version,
		$otherModid,
		$otherModName,
		[switch] $alsoLoadBefore,
		[switch] $rimThreaded,
		[switch] $autotest,
		[switch] $force,
		[switch] $lastVersion,
		[switch] $bare)
	if (-not $version) {
		$version = "latest"
	}
	$currentDirectory = (Get-Location).Path
	if (-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
		WriteMessage -failure "Can only be run from somewhere under $localModFolder, exiting"
		return			
	}

	if ($otherModName) {
		if ($otherModName.StartsWith("Mlie.") ) {
			$mlieMod = $otherModName
		} else {
			$modLink = Get-ModLink -modName $otherModName -chooseIfNotFound -lastVersion:$lastVersion
			if (-not $modLink) {
				WriteMessage -failure "Could not find other mod named $otherModName, exiting"
				return			
			}
			$otherModid = $modLink.Split('=')[1]
		}
	}

	$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\")[0]
	if ($autotest) {
		WriteMessage -progress "Auto-testing $modName"
	} else {
		WriteMessage -progress "Testing $modName"		
	}
	return Start-RimWorld -testMod $modName -version $version -alsoLoadBefore:$alsoLoadBefore -autotest:$autotest -force:$force -rimthreaded:$rimThreaded -bare:$bare -otherModid $otherModid -mlieMod $mlieMod
}

#endregion

#region Mod-descriptions

# Cleans the mod-description from broken chars
function Set-CleanModDescription {
	param(
		$modName,
		[switch]$noWait
	)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}
	if (-not (Get-OwnerIsMeStatus -modName $modName)) {
		WriteMessage -failure "$modName is not mine, aborting update"
		return
	}
	$modFolder = "$localModFolder\$modName"
	$aboutFile = "$($modFolder)\About\About.xml"		
	$aboutContent = Get-Content $aboutFile -Raw -Encoding UTF8
	if (-not ($aboutContent -match "&apos;") -and -not ($aboutContent -match "&quot;") -and -not ($aboutContent -match "&lt;") -and -not ($aboutContent -match "&gt;")) {
		WriteMessage -progress "Local description for $modName does not need cleaning"
		return		
	}
	WriteMessage -success "Starting with $modName"
	Sync-ModDescriptionFromSteam
	$aboutContent = Get-Content $aboutFile -Raw -Encoding UTF8
	$aboutContent = $aboutContent.Replace("&quot;", '"').Replace("&apos;", "'").Replace("&lt;", "").Replace("&gt;", "")
	$aboutContent | Set-Content -Path $aboutFile -Encoding UTF8
	Sync-ModDescriptionToSteam
	if ($noWait) {
		return
	}
	Get-ModPage
	Read-Host "Continue?"
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
		WriteMessage -warning "No description found on steam for $modName"
		return			
	}
	$currentDescription = Get-Content -Path $tempDescriptionFile -Raw -Encoding UTF8
	if ($currentDescription.Length -eq 0) {
		WriteMessage -warning "Description found on steam for $modName was empty"
		return		
	}

	return $currentDescription
}


# Replaces a string in all descriptions
function Update-ModDescription {
	param([string[]]$searchStrings,
		[string[]]$replaceStrings,
		$modName,
		[switch]$all,
		[switch]$syncBefore,
		[switch]$mineOnly,
		[switch]$notMine,
		$waittime = 500)

	if (-not $searchStrings) {
		WriteMessage -failure "Searchstrings must be defined"
		return	
	}
	if (-not $replaceStrings) {
		$result = Read-Host "Replacestring is not defined, continue? (y/n)"
		if ($result -eq "y") {
			return
		}	
	} else {
		if ($searchStrings.Count -ne $replaceStrings.Count) {
			WriteMessage -failure "If replacestrings are defined, they must be the same amount as searchstrings"
			return	
		}
	}
	$modFolders = @()
	if (-not $all) {
		if (-not $modName) {
			$modName = Get-CurrentModNameFromLocation
			if (-not $modName) {
				return
			}
		}

		$modFolder = "$localModFolder\$modName"
		if (-not (Test-Path $modFolder)) {
			WriteMessage -failure "$modFolder can not be found, exiting"
			return	
		}
		$modFolders += $modFolder
	} else {
		(Get-ChildItem -Directory $localModFolder).FullName | ForEach-Object { $modFolders += $_ }
	}
	
	WriteMessage -success "Will replace $($searchStrings -join ",") with $($replaceStrings -join ",") in $($modFolders.Count) mods" 
	$total = $modFolders.Count
	$i = 0
	$applicationPath = "$($settings.script_root)\SteamDescriptionEdit\Compiled\SteamDescriptionEdit.exe"
	foreach ($folder in ($modFolders | Get-Random -Count $modFolders.Count)) {		
		$i++	
		$percent = [math]::Round($i / $total * 100)
		$modNameString = $(Split-Path $folder -Leaf)
		Write-Progress -Activity "$($modFolders.Count) matches found, looking in $($folder.name), " -Status "$i of $total" -PercentComplete $percent;
		if (-not (Test-Path "$($folder)\About\PublishedFileId.txt")) {
			WriteMessage -progress "$modNameString is not published, ignoring"
			continue
		}		
		if (-not (Get-OwnerIsMeStatus -modName $modNameString)) {
			WriteMessage -progress "$modNameString is not mine, ignoring"
			continue
		}
		$modId = Get-Content "$($folder)\About\PublishedFileId.txt" -Raw
		$aboutFile = "$($folder)\About\About.xml"
		$isContinued = Get-IsModContinued -modName $modNameString
		if ($notMine -and -not $isContinued) {
			WriteMessage -progress "$modNameString is mine, ignoring"
			continue
		}
		if ($mineOnly -and $isContinued) {
			WriteMessage -progress "$modNameString is not mine, ignoring"
			continue
		}
		if ($syncBefore) {			
			Sync-ModDescriptionFromSteam -modName $modNameString
		}	
		$aboutContent = [xml](Get-Content $aboutFile -Raw -Encoding UTF8)
		for ($i = 0; $i -lt $searchStrings.Count; $i++) {
			$searchString = $searchStrings[$i]
			if ($replaceStrings) {
				$replaceString = $replaceStrings[$i]
			}
			if ($replaceStrings -and (Select-String -InputObject $aboutContent.ModMetaData.description -pattern $replaceString)) {
				WriteMessage -progress "Description for $modNameString already contains the replace-string, skipping"
				continue
			}
			if (Select-String -InputObject $aboutContent.ModMetaData.description -pattern $searchString) {
				Start-Sleep -Milliseconds $waittime
				$arguments = @($modId, "REPLACE", $searchString, $replaceString)   
				Start-Process -FilePath $applicationPath -ArgumentList $arguments -Wait -NoNewWindow
				$aboutContent.ModMetaData.description = $aboutContent.ModMetaData.description.Replace($searchString, $replaceString)
			} else {
				WriteMessage -progress "Description for $modNameString does not contain $searchString"
			}
		}
		$aboutContent.Save($aboutFile)
		WriteMessage -success "Updated description for $modNameString"
	}	
}

# Replaces the decsription with what is set on the steam-page
function Sync-ModDescriptionFromSteam {
	param($modName,
		[switch]$Force)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}

	$modFolder = "$localModFolder\$modName"
	if (-not (Test-Path $modFolder)) {
		WriteMessage -failure "$modFolder can not be found, exiting"
		return	
	}
	if (-not $Force -and -not (Get-OwnerIsMeStatus -modName $modName)) {
		WriteMessage -failure "$modName is not mine, aborting sync"
		return
	}
	if (-not (Test-Path "$($modFolder)\About\PublishedFileId.txt")) {
		WriteMessage -failure "$modName not published, aborting sync"
		return
	}	
	$applicationPath = "$($settings.script_root)\SteamDescriptionEdit\Compiled\SteamDescriptionEdit.exe"
	$modId = Get-Content "$($modFolder)\About\PublishedFileId.txt" -Raw
	$stagingDirectory = $settings.mod_staging_folder
	$tempDescriptionFile = "$stagingDirectory\tempdesc.txt"
	Remove-Item -Path $tempDescriptionFile -Force -ErrorAction SilentlyContinue
	$arguments = @($modId, "SAVE", $tempDescriptionFile)
	Start-Process -FilePath $applicationPath -ArgumentList $arguments -Wait -NoNewWindow
	if (-not (Test-Path $tempDescriptionFile)) {
		WriteMessage -failure "No description found on steam for $modName, aborting sync"
		return
	}
	$currentDescription = Get-Content -Path $tempDescriptionFile -Raw -Encoding UTF8
	if ($currentDescription.Length -eq 0) {
		WriteMessage -failure "Description found on steam for $modName was empty, aborting sync"
		return
	}
	$aboutFile = "$($modFolder)\About\About.xml"
	$aboutContent = [xml](Get-Content $aboutFile -Raw -Encoding UTF8)
	$aboutContent.ModMetaData.description = $currentDescription.Replace(" & ", " &amp; ").Replace(">", "").Replace("<", "")
	$aboutContent.Save($aboutFile)
}

# Replaces the steam mod-description with the local description
function Sync-ModDescriptionToSteam {
	param($modName,
		[switch]$Force)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}

	$modFolder = "$localModFolder\$modName"
	if (-not (Test-Path $modFolder)) {
		WriteMessage -failure "$modFolder can not be found, exiting"
		return	
	}
	if (-not $Force -and -not (Get-OwnerIsMeStatus -modName $modName)) {
		WriteMessage -failure "$modName is not mine, aborting sync"
		return
	}
	if (-not (Test-Path "$($modFolder)\About\PublishedFileId.txt")) {
		WriteMessage -failure "$modName not published, aborting sync"
		return
	}	
	$applicationPath = "$($settings.script_root)\SteamDescriptionEdit\Compiled\SteamDescriptionEdit.exe"
	$stagingDirectory = $settings.mod_staging_folder
	$tempDescriptionFile = "$stagingDirectory\tempdesc.txt"
	$aboutContent = Get-ModAboutFile -modName $modName -xml
	if (-not $aboutContent) {
		return
	}
	$aboutContent.ModMetaData.description | Set-Content -Path $tempDescriptionFile -Encoding UTF8
	$modId = Get-Content "$($modFolder)\About\PublishedFileId.txt" -Raw
	$arguments = @($modId, "SET", $tempDescriptionFile)
	Start-Process -FilePath $applicationPath -ArgumentList $arguments -Wait -NoNewWindow
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
		[switch]$SelectFolder,
		[switch]$SkipNotifications,
		[switch]$GithubOnly,
		[string]$ChangeNote,
		[string]$ExtraInfo,
		[switch]$EndOfLife,
		[switch]$Force,
		[switch]$Auto
	)
	if ($SelectFolder) {
		$modFolder = Get-Folder 
		if (-not $modFolder) {
			WriteMessage -failure "No folder selected, exiting"
			return
		}
		$modName = Split-Path -Leaf $modFolder
	} else {
		$currentDirectory = (Get-Location).Path
		if (-not $currentDirectory.StartsWith($localModFolder) -or $currentDirectory -eq $localModFolder) {
			WriteMessage -failure "Can only be run from somewhere under $localModFolder, exiting"
			return			
		}
		$modName = $currentDirectory.Replace("$localModFolder\", "").Split("\\")[0]
		$modFolder = "$localModFolder\$modName"
	}
	if (-not $Force -and -not (Get-OwnerIsMeStatus -modName $modName)) {
		WriteMessage -failure "$modName is not mine, aborting publish"
		return
	}

	$modNameClean = $modName.Replace("+", "Plus")
	$stagingDirectory = $settings.mod_staging_folder
	$manifestFile = "$modFolder\About\Manifest.xml"
	$modsyncFile = "$modFolder\About\ModSync.xml"
	$aboutFile = "$modFolder\About\About.xml"
	$modIconFile = "$modFolder\About\ModIcon.png"
	$readmeFile = "$modFolder\README.md"
	$previewFile = "$modFolder\About\Preview.png"
	$gitIgnorePath = "$modFolder\.gitignore"
	$modPublisherPath = "$modFolder\_PublisherPlus.xml"
	$reapplyGitignore = $false
	$gitApiToken = $settings.github_api_token

	# Clean up XML-files
	$files = Get-ChildItem "$modFolder\*.xml" -Recurse
	foreach ($file in $files) {
		if ($file.BaseName -eq "_PublisherPlus") {
			continue
		}
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
			return
		}
		$fileContent.Save($file.FullName)
		if (-not ($file.Extension -ceq ".xml")) { 
			Move-Item $file.FullName $file.FullName.Replace($file.Extension, ".xml")
		}
	}

	$aboutContent = [xml](Get-Content $aboutFile -Raw -Encoding UTF8)
	$modFullName = $aboutContent.ModMetaData.name

	if (-not (Test-Path $previewFile)) {
		Read-Host "Preview-file does not exist, create one then press Enter"
	}

	if ((Get-Item $previewFile).Length -ge 1MB) {
		WriteMessage -warning "Preview-file is too large, resizing"
		Set-ImageSizeBelow -imagePath $previewFile -sizeInKb 999 -removeOriginal
	}

	# Remove leftover-files
	if (Test-Path "$modFolder\Source\lastrun.log") {
		Remove-Item "$modFolder\Source\lastrun.log" -Force
	}

	# Auto-translate keyed files if needed
	if (-not $EndOfLife -and ((Get-Date) -gt (Get-Date -Year 2022 -Month 11 -Day 11))) {
		$extraCommitInfo = Update-KeyedTranslations -modName $modName -silent -force:$Force
	}

	# Mod Manifest
	if (-not (Test-Path $manifestFile)) {
		Copy-Item -Path $manifestTemplate $manifestFile -Force | Out-Null
		((Get-Content -path $manifestFile -Raw -Encoding UTF8).Replace("[modname]", $modNameClean).Replace("[username]", $settings.github_username)) | Set-Content -Path $manifestFile -Encoding UTF8
		$manifestContent = [xml](Get-Content -path $manifestFile -Raw -Encoding UTF8)
		$version = Get-NextVersionNumber -currentVersion (Get-CurrentRimworldVersion -versionObject)
		$manifestContent.Manifest.version = $version.ToString()
		$manifestContent.Save($manifestFile)
	} else {
		$manifestContent = [xml](Get-Content -path $manifestFile -Raw -Encoding UTF8)
		$currentIdentifier = $manifestContent.Manifest.identifier
		$version = [version]$manifestContent.Manifest.version
		if ($currentIdentifier -ne $modNameClean) {
			$manifestContent.Manifest.identifier = $modNameClean
			$manifestContent.Save($manifestFile)
		}
	}
	if (Test-Path $licenseFile) {
		if (Test-Path $modFolder\LICENSE) {
			Remove-Item -Path "$modFolder\LICENSE" -Force
		}
		if (-not (Test-Path $modFolder\LICENSE.md)) {
			Copy-Item -Path $licenseFile $modFolder\LICENSE.md -Force | Out-Null
		} else {
			if ((Get-Item -Path $modFolder\LICENSE.md).LastWriteTime -lt (Get-Item $licenseFile).LastWriteTime) {
				Copy-Item -Path $licenseFile $modFolder\LICENSE.md -Force | Out-Null
			}
		}
	}
	if (-not (Test-Path $gitIgnorePath) -or ((Get-Item $gitignoreTemplate).LastWriteTime -gt (Get-Item $gitIgnorePath).LastWriteTime)) {
		Copy-Item -Path $gitignoreTemplate $gitIgnorePath -Force | Out-Null
		$reapplyGitignore = $true
	} 
	if ((Test-Path $modSyncTemplate) -and -not (Test-Path $modsyncFile)) {
		New-ModSyncFile -targetPath $modsyncFile -modWebPath $modNameClean -modname $modFullName -version $version.ToString()
	}
	if ((Test-Path $publisherPlusTemplate) -and -not (Test-Path $modPublisherPath) -or ((Get-Item $publisherPlusTemplate).LastWriteTime -gt (Get-Item $modPublisherPath).LastWriteTime)) {
		Copy-Item -Path $publisherPlusTemplate $modPublisherPath -Force | Out-Null
		((Get-Content -path $modPublisherPath -Raw -Encoding UTF8).Replace("[modpath]", $modFolder)) | Set-Content -Path $modPublisherPath
	}

	$modIdPath = "$modFolder\About\PublishedFileId.txt"
	$firstPublish = (-not (Test-Path $modIdPath))
	# Create repo if does not exists
	if ((Get-RepositoryStatus -repositoryName $modNameClean) -eq $true) {
		if ($ChangeNote) {
			$message = $ChangeNote
		} elseif ($EndOfLife) {
			$message = "Last update, added end-of-life message"
		} else {
			$message = Get-MultilineMessage -query "Changenote" -mustFill
		}
		$oldVersion = $version.ToString()
		$newVersion = (Get-NextVersionNumber -currentVersion $version).ToString()
		((Get-Content -path $manifestFile -Raw -Encoding UTF8).Replace($oldVersion, $newVersion)) | Set-Content -Path $manifestFile
		((Get-Content -path $modsyncFile -Raw -Encoding UTF8).Replace($oldVersion, $newVersion)) | Set-Content -Path $modsyncFile
		if ($EndOfLife) {
			Set-ModUpdateFeatures -modName $modNameClean -updateMessage "The original version of this mod has been updated, please use it instead. This version will remain, but unlisted and will not be updated further."
		} elseif (-not $ChangeNote) {
			Set-ModUpdateFeatures -ModName $modNameClean -Force:$Force
		}
	} else {
		Read-Host "Repository could not be found, create $modNameClean?"
		New-GitRepository -repoName $modNameClean
		Get-LatestGitVersion
		$message = "First publish"
		$newVersion = $version.ToString()
	}

	if ($extraCommitInfo) {
		$message += ".`r`n$extraCommitInfo"
	}

	$version = [version]$newVersion
	Set-ModChangeNote -ModName $modName -Changenote "$version - $message" -Force:$Force
	if ($firstPublish) {		
		Update-ModDescriptionFromPreviousMod -noConfimation -localSearch -modName $modName -Force:$Force
		Update-ModUsageButtons -modName $modName -silent
	} else {
		Sync-ModDescriptionFromSteam -modName $modName -Force:$Force
	}
	$aboutContent = [xml](Get-Content $aboutFile -Raw -Encoding UTF8)
	$reuploadDescription = $false
	if (-not $firstPublish) {
		$description = $aboutContent.ModMetaData.description
		$modId = Get-Content $modIdPath -Raw -Encoding UTF8
		$indexOfIt = $description.IndexOf("[url=https://steamcommunity.com/sharedfiles/filedetails/changelog/$modId]Last updated")
		if ($indexOfIt -ne -1) {
			$description = $description.SubString(0, $indexOfIt).Trim()
		}
		$aboutContent.ModMetaData.description = "$description`n[url=https://steamcommunity.com/sharedfiles/filedetails/changelog/$modId]Last updated $(Get-Date -Format "yyyy-MM-dd")[/url]"
		$reuploadDescription = $true
	}
	$continuedMod = Get-IsModContinued -modName $modName
	if ($continuedMod -and -not $aboutContent.ModMetaData.description.Contains("PwoNOj4")) {
		$aboutContent.ModMetaData.description += $faqText
		if (-not $firstPublish) {
			$reuploadDescription = $true
		}
	}	
	if (-not $continuedMod -and -not $aboutContent.ModMetaData.description.Contains("5xwDG6H")) {
		$aboutContent.ModMetaData.description += $faqTextPrivate
		if (-not $firstPublish) {
			$reuploadDescription = $true
		}
	}
	if (-not (Test-Path $modIconFile)) {
		$modIcon = "E:\ModPublishing\Self-ModIcon.png"
		if ($continuedMod) {
			$modIcon = "E:\ModPublishing\ModIcon.png"
		}
		Copy-Item $modIcon $modIconFile -Force -Confirm:$false
		WriteMessage -success "Added mod-icon to about-folder"
	}
	Add-VersionTagOnImage -modName $modName
	if ($EndOfLife) {
		$aboutContent.ModMetaData.description = $aboutContent.ModMetaData.description.Replace("pufA0kM", "CN9Rs5X")
		$reuploadDescription = $true
	}
	if ($reuploadDescription) {
		$aboutContent.ModMetaData.description = $aboutContent.ModMetaData.description.Trim()
		$aboutContent.Save($aboutFile)
		Sync-ModDescriptionToSteam -modName $modName -Force:$Force
		WriteMessage -message "Updated the description" -success
	}

	# Clone current repository to staging
	# git clone https://github.com/$($settings.github_username)/$modNameClean

	# Copy replace modfiles
	"# $modNameClean`n`r" > $readmeFile
	(Convert-BBCodeToGithub -textToConvert $aboutContent.ModMetaData.description) >> $readmeFile
	# robocopy $modFolder $stagingDirectory\$modNameClean /MIR /w:10 /XD .git /NFL /NDL /NJH /NJS /NP
	# Set-Location -Path $stagingDirectory\$modNameClean
	Set-SafeGitFolder
	# Reapply gitignore-file if necessary
	if ($reapplyGitignore) {
		git rm -r --cached .
	}

	git add .
	git commit -S -m $message
	git push origin
	git tag -s -a $newVersion -m $message
	git push --tags

	$releaseData = @{
		tag_name = $newVersion;
		name     = $message;
	}
	$releaseParams = @{
		Uri         = "https://api.github.com/repos/$($settings.github_username)/$modNameClean/releases";
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
	Get-ZipFile -modname $modName -filename "$($modNameClean)_$newVersion.zip"
	$zipFile = Get-Item "$localModFolder\$modname\$($modNameClean)_$newVersion.zip"
	$fileName = $zipFile.Name
	$uploadParams = @{
		Uri     = "https://uploads.github.com/repos/$($settings.github_username)/$modNameClean/releases/$($createdRelease.id)/assets?name=$fileName&label=$fileName";
		Method  = 'POST';
		Headers = @{
			Authorization = 'Basic ' + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($gitApiToken + ":x-oauth-basic"));
		}
	}

	WriteMessage -progress "Uploading zip-file"
	$uploadedFile = Invoke-RestMethod @uploadParams -InFile $zipFile.FullName -ContentType "application/zip"
	WriteMessage -progress "Upload status: $($uploadedFile.state)"
	Remove-Item $zipFile.FullName -Force
	# Set-Location $modFolder

	if ($EndOfLife) {
		Set-GitRepositoryToArchived -repoName $modNameClean
	} else {
		Set-GitSubscriptionStatus -repoName $modNameClean -enabled $true
		Set-GithubIssueWebhook -repoName $modNameClean
	}
	if ($GithubOnly) {
		WriteMessage -warning "Published $modName to github only!"
		return
	}

	Start-SteamPublish -modFolder $modFolder -Force:$Force

	if (-not $SkipNotifications -and (Test-Path $modIdPath)) {
		if ($firstPublish) {
			Push-UpdateNotification
			Get-ModPage
			if ($aboutContent.ModMetaData.description -match "https://steamcommunity.com/sharedfiles/filedetails") {
				$previousModId = (($aboutContent.ModMetaData.description -split "https://steamcommunity.com/sharedfiles/filedetails/\?id=")[1] -split "[^0-9]")[0]
				$trelloCard = Find-TrelloCardByCustomField -text "https://steamcommunity.com/sharedfiles/filedetails/?id=$previousModId" -fieldId $trelloLinkId
				if ($trelloCard) {
					Move-TrelloCardToDone -cardId $trelloCard.id
				}
			}
		} else {
			if (-not $Auto) {
				Close-TrelloCardsForMod -modName $modName
			}
			
			if ($ExtraInfo) {
				$message = "$message - $ExtraInfo"
			}
			Push-UpdateNotification -Changenote "$version - $message"
		}
	}
	if ($EndOfLife) {
		WriteMessage -success "Repository set to archived, mod set to unlisted. Moving local mod-folder to Archived"
		Push-UpdateNotification -Changenote "Original version updated, mod set to unlisted. Will not be further updated" -EndOfLife
		Get-ModPage
		Set-Location $localModFolder
		Move-Item -Path $modFolder -Destination "$stagingDirectory\..\Archive\" -Force -Confirm:$false
		WriteMessage -success "Archived $modName"
		return
	}
	WriteMessage -success "Published $modName - $(Get-ModPage -getLink)"
}

# Steam-publishing
function Start-SteamPublish {
	param($modFolder,
		[switch]$Force,
		[switch]$Confirm)

	if (-not (Test-Path $modFolder)) {
		WriteMessage -failure "$modfolder does not exist"
		return
	}
	if (-not $Force -and -not (Get-OwnerIsMeStatus -modName $(Split-Path $modfolder -Leaf))) {
		WriteMessage -failure "$(Split-Path $modfolder -Leaf) is not mine, aborting update"
		return
	}
	$copyPublishedFileId = $false
	if (!(Test-Path "$modFolder\About\PublishedFileId.txt")) {
		$copyPublishedFileId = $true
	}
	$stagingDirectory = $settings.mod_staging_folder
	$previewDirectory = "$($settings.mod_staging_folder)\..\PreviewStaging"
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse
	Get-ChildItem -Path $stagingDirectory -Recurse | Remove-Item -force -recurse
	Get-ChildItem -Path $previewDirectory -Recurse | Remove-Item -force -recurse
	Get-ChildItem -Path $previewDirectory -Recurse | Remove-Item -force -recurse

	WriteMessage -progress "Copying mod-files to publish-dir"
	$exclusions = @()
	$exclusionFile = "$modfolder\_PublisherPlus.xml"
	if ((Test-Path $exclusionFile)) {
		foreach ($exclusion in ([xml](Get-Content $exclusionFile -Raw -Encoding UTF8)).Configuration.Excluded.exclude) {
			$exclusions += $exclusion.Replace("$modFolder\", "")
		}
		$exclusions += $exclusionFile.Replace("$modFolder\", "")
	}
	Copy-Item -Path "$modFolder\*" -Destination $stagingDirectory -Recurse -Exclude $exclusions
	if ($copyPublishedFileId -or $Force) {
		WriteMessage -progress "Copying previewfiles to preview-dir"
		$inclusions = @("*.png", "*.jpg", "*.gif")
		Copy-Item -Path "$modfolder\Source\*" -Destination $previewDirectory -Include $inclusions
	}
	if (Test-Path "$modfolder\Source\Preview.gif") {
		Copy-Item -Path "$modfolder\Source\Preview.gif" -Destination $previewDirectory		
	}

	WriteMessage -progress "Starting steam-publish"
	$publishToolPath = "$($settings.script_root)\SteamUpdateTool\Compiled\RimworldModReleaseTool.exe"
	$arguments = @($stagingDirectory, $previewDirectory)
	if ($Confirm) {
		$arguments += "True"
	}
	Start-Process -FilePath $publishToolPath -ArgumentList $arguments -Wait -NoNewWindow
	if ($copyPublishedFileId -and (Test-Path "$stagingDirectory\About\PublishedFileId.txt")) {
		Copy-Item -Path "$stagingDirectory\About\PublishedFileId.txt" -Destination "$modfolder\About\PublishedFileId.txt" -Force
	}
}

# Simple update-notification for Discord
function Push-UpdateNotification {
	param(
		[switch]$Test, 
		[string]$Changenote, 
		[switch]$EndOfLife
	)
	$modName = Get-CurrentModNameFromLocation
	if (-not $modName) {
		return
	}
	$modFolder = "$localModFolder\$modName"
	$aboutContent = Get-ModAboutFile -modName $modName -xml
	if (-not $aboutContent) {
		return
	}

	$modFileId = "$modFolder\About\PublishedFileId.txt"
	$modId = Get-Content $modFileId -Raw -Encoding UTF8
	$modFullName = $aboutContent.ModMetaData.name
	$modUrl = "https://steamcommunity.com/sharedfiles/filedetails/?id=$modId"

	if ($EndOfLife) {
		$discordHookUrl = $discordRemoveHookUrl
		$repoUrl = Get-ModRepository -getLink
		$content = (Get-Content $discordRemoveMessage -Raw -Encoding UTF8).Replace("[modname]", $modFullName).Replace("[repourl]", $repoUrl).Replace("[endmessage]", $Changenote)
	} else {
		if ($Changenote.Length -gt 0) {
			$discordHookUrl = $discordUpdateHookUrl
			$content = (Get-Content $discordUpdateMessage -Raw -Encoding UTF8).Replace("[modname]", $modFullName).Replace("[modurl]", $modUrl).Replace("[changenote]", $Changenote)
		} else {
			$discordHookUrl = $discordPublishHookUrl
			$content = (Get-Content $discordPublishMessage -Raw -Encoding UTF8).Replace("[modname]", $modFullName).Replace("[modurl]", $modUrl)
		}		
	}
	
	if ($Test) {
		$discordHookUrl = $discordTestHookUrl
		Write-Host "Posting the message to test-channel"
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
		& magick convert "$baseImagePath" -background transparent -gravity center -extent "$($newWidth)x$($newHeight)" "$newTempPath"
		$baseImage = $newTempPath
	}

	$tagWidth = [math]::Round($previewImage.Width / 6, 3)
	$tagHeight = [math]::Round(($tagWidth / $previewImage.Width) * $previewImage.Height, 3)
	$tagMargin = [math]::Round($previewImage.Width / 50, 3)

	if (Test-Path $outputPath) {
		Remove-Item $outputPath -Force -Confirm:$false | Out-Null
	}
	& magick convert "$baseImage" "$overlayImagePath" -gravity NorthEast -geometry "$($tagWidth)x$($tagHeight)+$tagMargin+$tagMargin" -composite "$outputPath"
}

function Set-ImageSizeBelow {
	param (
		$imagePath,
		$sizeInKb,
		[switch]$removeOriginal
	)
	if (-not (Test-Path $imagePath)) {
		Write-Host "Cannot find image at $imagePath, exiting"
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
			Write-Host "At 0 percent, cannot lower size any more"
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
		Write-Host "Cannot find image at $imagePath, exiting"
		return
	}
	if (-not $percent) {
		Write-Host "Must define a resize percent"
		return
	}
	$originalFile = Split-Path -Leaf $imagePath
	$outPath = $imagePath.Replace($originalFile, $outName)
	if (Test-Path $outPath) {
		if ($overwrite) {
			Remove-Item $outPath -Confirm:$false -Force | Out-Null
		} else {
			Write-Host "$outPath already exists, remove it first"
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
		Write-Host "Saved the resized image to $outPath"
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
		[string] $modName,
		[switch] $force
	)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}

	$previewPath = "$localModFolder\$modName\About\Preview.png"
	if (-not (Test-Path $previewPath)) {
		WriteMessage -failure "Found no preview image to create a banner from"
		return
	}
	$aboutFile = Get-ModAboutFile -modName $modName
	if (-not $aboutFile) {
		WriteMessage -failure "Found no about-file to get the modname from"
		return
	}

	$updatebannerPath = "$localModFolder\$modName\Textures\UpdateInfo\$($modName).png"
	$updatebannerTempPath = "$localModFolder\$modName\Textures\UpdateInfo\$($modName)_temp.png"
	if (-not $force -and (Test-Path $updatebannerPath)) {
		return
	}

	$modDisplayName = ([xml]$aboutFile).ModMetaData.Name.Replace(" (Continued)", "")
	$updatebannerFolder = Split-Path $updatebannerPath
	if (-not (Test-Path $updatebannerFolder)) {
		New-Item -Path $updatebannerFolder -ItemType Directory -Force | Out-Null
	}

	Add-Type -AssemblyName System.Drawing

	Copy-Item $previewPath $updatebannerTempPath -Force
	Set-ImageMaxSize -imagePath $updatebannerTempPath -pixels 200 -outName (Split-Path $updatebannerTempPath -Leaf) -overwrite -silent
	$tempImageObject = [System.Drawing.Image]::FromFile($updatebannerTempPath)
	$height = $tempImageObject.Height
	$tempImageObject.Dispose() 

	& magick convert "$updatebannerTempPath" -background transparent -gravity West -extent "$(500)x$($height)" "$updatebannerPath"
	Remove-Item $updatebannerTempPath -Force
	Move-Item $updatebannerPath $updatebannerTempPath -Force

	& magick convert -background transparent -gravity West -font RimWordFont -fill 'rgba(222,222,222,1)' -size "$(275)x$($height * 0.9)" caption:"$modDisplayName" "$updatebannerTempPath" +swap -gravity East -composite "$updatebannerPath"
	Remove-Item $updatebannerTempPath -Force
}

function Verify-ModPreviewImages {
	
	param (
		[string] $modName
	)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}

	$modLink = Get-ModPage -modName $modName -getLink
	$imagesLink = $modLink.Replace("filedetails", "managepreviews") 

	Import-Module -ErrorAction Stop PowerHTML -Verbose:$false
	$page = ConvertFrom-Html -URI $imagesLink


}


#endregion

#region Translations

# Translation of key-files
function Update-KeyedTranslations {
	param (
		$modName,
		[switch]$test,
		[switch]$silent,
		[switch]$force
	)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}
	
	if (-not (Get-OwnerIsMeStatus -modName $modName) -and -not $force) {
		WriteMessage -failure "$modName is not mine, aborting update"
		return
	}
	$modFolder = "$localModFolder\$modName"

	$allLanguagesFolders = Get-ChildItem -Path $modFolder -Recurse -Include "Languages" -Directory

	if (-not $allLanguagesFolders) {
		if (-not $silent) {
			WriteMessage -progress "No translation-files found for $modName, ignoring"
		}
		return
	}
	$updatedLanguages = @()
	$baseXml = @"
<?xml version="1.0" encoding="utf-8"?>
"@
	foreach ($folder in $allLanguagesFolders) {
		if (-not (Test-Path "$($folder.FullName)\English\Keyed")) {
			continue
		}
		$keyedSourceFiles = Get-ChildItem -Path "$($folder.FullName)\English\Keyed" -File

		if (-not $keyedSourceFiles) {
			WriteMessage -warning "$modName has empty translation-folder: $($folder.FullName)\English\Keyed"
			continue
		}

		foreach ($language in $autoTranslateLanguages) {
			if (-not (Test-Path "$($folder.FullName)\$language")) {
				Write-Progress "No translation found for $language, autocreating"
				New-Item "$($folder.FullName)\$language" -ItemType Directory | Out-Null
			}
		}

		$allNonEnglishFolders = Get-ChildItem -Path $folder.FullName -Directory -Exclude "English"
		if (-not $allNonEnglishFolders) {
			continue
		}
		foreach ($languageFolder in $allNonEnglishFolders) {
			if ($languages -notcontains $languageFolder.Name) {
				WriteMessage -warning "$($languageFolder.Name) can not be translated by DeepL"
				continue
			}
			$translateTo = $shorts[$languages.IndexOf($languageFolder.Name)]
			$keyedFolder = "$($languageFolder.FullName)\Keyed"
			if (-not (Test-Path $keyedFolder)) {
				New-Item "$($languageFolder.FullName)\Keyed" -ItemType Directory | Out-Null
			}
			$languageUpdated = $false
			foreach ($file in $keyedSourceFiles) {
				$currentKeyedFilePath = "$keyedFolder\$($file.Name)"
				if (-not (Test-Path $currentKeyedFilePath)) {
					WriteMessage -warning "$modName has missing translation-file: '$currentKeyedFilePath'. Creating..."
					if ($test) {
						WriteMessage -progress "Would have created $currentKeyedFilePath"
						continue
					} else {
						WriteMessage -progress "Creating $($file.Name) for $($languageFolder.Name) in $modName"
						$baseXml | Out-File -FilePath $currentKeyedFilePath -Encoding utf8
					}
				}
				$commentExists = $false
				if (Select-String -Path $currentKeyedFilePath -Pattern "DeepL") {
					$commentExists = $true
				}
				$englishContent = [xml](Get-Content -Path "$($file.FullName)" -Encoding utf8)
				$localContent = [xml](Get-Content -Path $currentKeyedFilePath -Encoding utf8)
				if (-not $localContent.LanguageData) {
					$languageData = $localContent.CreateElement("LanguageData")
					$localContent.AppendChild($languageData) | Out-Null
				}
				$resaveFile = $false
				$nodeCount = 0
				foreach ($childNode in $englishContent.LanguageData.ChildNodes) {
					$nodeCount++
					if ($localContent.LanguageData."$($childNode.Name)") {
						continue
					}
					if (-not $commentExists) {
						$commentExists = $true
						if ($test) {
							WriteMessage -progress "Would have added a DeepL translation-comment to $currentKeyedFilePath"
						} else {
							WriteMessage -progress "Adding DeepL translation-comment to $currentKeyedFilePath"
							$comment = $localContent.CreateComment("The following translations were generated by https://www.deepl.com/")
							if ($localContent.LanguageData.ChildNodes) {
								$localContent.LanguageData.AppendChild($comment) | Out-Null
							} else {
								$localContent.DocumentElement.AppendChild($comment) | Out-Null
							}
						}
					}
					if ($childNode.NodeType -eq "Comment") {
						$comment = $localContent.CreateComment($childNode.Value)
						$localContent.LanguageData.AppendChild($comment) | Out-Null
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
							WriteMessage -progress "Would have translated '$textToTranslate' to $translateTo and added it to $currentKeyedFilePath"
							continue
						}
						$translatedString = Get-DeeplTranslation -text $textToTranslate -selectedTo $translateTo -silent:$silent						
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
							WriteMessage -progress "Would have translated '$textToTranslate', a $($textStrings.Length) part string to $translateTo and added it to $currentKeyedFilePath. Strings: $textStrings, Numbers: $numbers"
							continue
						}
						if ($textStrings[0] -eq "<") {
							$translatedString = ""
						} else {
							$translatedString = Get-DeeplTranslation -text $textStrings[0] -selectedTo $translateTo -silent:$silent
						}
						for ($i = 0; $i -lt $numbers.Count; $i++) {
							$translatedString += " { $($numbers[$i]) }"
							if ($textStrings[$i + 1] -and $textStrings[$i + 1] -ne "<") {
								$translatedString += Get-DeeplTranslation -text $textStrings[$i + 1] -selectedTo $translateTo -silent:$silent
							}
						}
					}
					if (-not $textToTranslate.EndsWith(" ")) {
						$translatedString = $translatedString.Trim()
					}
					if (-not $translatedString) {
						continue
					}
					$nodeToAdd = $localContent.CreateElement($childNode.Name)
					if ($cdata) {
						$textToAddToNode = $localContent.CreateCDataSection($translatedString)
					} else {
						$textToAddToNode = $localContent.CreateTextNode($translatedString)
					}
					$nodeToAdd.AppendChild($textToAddToNode) | Out-Null
					$localContent.LanguageData.AppendChild($nodeToAdd) | Out-Null
					$resaveFile = $true
				}
				if ($resaveFile) {
					WriteMessage -success "Added automatic translations to $currentKeyedFilePath"
					$localContent.Save($currentKeyedFilePath)
					$languageUpdated = $true
				}
			}
			if ($languageUpdated) {
				$updatedLanguages += $languageFolder.Name
			}
		}
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
		Write-Progress -Activity "Done" -Status "Ready" -Completed
		return "Used DeepL to update translations for $($updatedLanguages -join ", ")"
	}
}

# Def-inject template
function GenerateDefInjectTemplate {
	param (
		$modName,
		[switch]$test,
		[switch]$silent,
		[switch]$force,
		$outPath
	)
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}
	
	if (-not (Get-OwnerIsMeStatus -modName $modName) -and -not $force) {
		WriteMessage -failure "$modName is not mine, aborting update"
		return
	}
	$modFolder = "$localModFolder\$modName"

	$defPath = "$modFolder\Defs"
	if (-not (Test-Path $defPath)) {
		$defPath = "$modFolder\$(Get-CurrentRimworldVersion)\Defs"
		if (-not (Test-Path $defPath)) {
			WriteMessage -message "Could not find any Defs to generate template from" -warning
			return
		}
	}
	WriteMessage -message "Using $defPath as def-folder" -progress

	if (-not $outPath -or -not (Test-Path $outPath)) {
		$outPath = "$modFolder\Source"
		if (-not (Test-Path $outPath)) {
			WriteMessage -message "$outPath does not exist" -warning
			return
		}
	}
	WriteMessage -message "Using $outPath as output path" -progress

	$outPath = "$outPath\EnglishTemplate"
	if (-not (Test-Path $outPath)) {
		New-Item $outPath -ItemType Directory | Out-Null
	}

	WriteMessage -message "All paths verified, extracting data" -progress

	$allDefFiles = Get-ChildItem -Path $defPath -Include *.xml -Recurse
	$counter = 0
	foreach ($folder in (Get-ChildItem -Path $defPath -Directory)) {
		Copy-Item $folder.FullName $outPath -Filter { PSIsContainer } -Recurse -Force
	}
	foreach ($file in $allDefFiles) {
		$xmlContent = [xml](Get-Content $file.FullName -Encoding utf8)
		$translation = GetDescriptiveStringsFromXmlNode -xmlNode $xmlContent.Defs
		if ($translation) {
			$translation = @"
<?xml version="1.0" encoding="UTF-8"?>
<LanguageData>
$translation
</LanguageData>
"@
			$translation | Out-File $file.FullName.Replace($defPath, $outPath) -Force -Encoding utf8
			$counter++
		}
	}

	WriteMessage -message "Created templates for $counter def xml-files" -success
}

# Fetch all relevant strings
function GetDescriptiveStringsFromXmlNode {
	param(
		$xmlNode,
		$pathSoFar
	)
	if (-not $pathSoFar -and $xmlNode.defName) {
		$pathSoFar = $xmlNode.defName
	} 
	$returnValue = ""
	
	if ($xmlNode.NodeType -eq "Comment") {
		return $returnValue
	}

	$namesToSave = @("label", "description", "jobString", "customLabel", "deathMessage", "fixedName", "pawnSingular", "pawnsPlural", "leaderTitle", "endMessage", "labelNoun", "beginLetter", "beginLetterLabel", "baseInspectLine")
	if ($namesToSave.Contains($xmlNode.Name)) {
		if ($xmlNode.ParentNode.Name -eq "li" -and $xmlNode.ParentNode.label) {
			$returnValue += "<$pathSoFar.$($xmlNode.ParentNode.label.Replace(" ", "_")).$($xmlNode.Name)>$($xmlNode.'#text')</$pathSoFar.$($xmlNode.ParentNode.label.Replace(" ", "_")).$($xmlNode.Name)>`n"
		} else {
			$returnValue += "<$pathSoFar.$($xmlNode.Name)>$($xmlNode.'#text')</$pathSoFar.$($xmlNode.Name)>`n"
		}
		return $returnValue
	}	
	
	if ($xmlNode.HasChildNodes) {
		if ($pathSoFar -and $pathSoFar -ne $xmlNode.defName -and $xmlNode.Name -ne "li") {
			$pathSoFar += ".$($xmlNode.Name)"
		}
		foreach ($childNode in $xmlNode.ChildNodes) {
			$returnValue += GetDescriptiveStringsFromXmlNode -xmlNode $childNode -pathSoFar $pathSoFar
		}
		return $returnValue
	}

	return $returnValue
}

# Generates the DeepL header for requests
function Get-DeeplAuthorizationHeader { 
	$header = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
	$header.Add('Authorization', "DeepL-Auth-Key $deeplApiKey")
	return $header
}

# Gets remaining characters to use from the DeepL service
function Get-DeeplRemainingCharacters {
	$result = Invoke-RestMethod -Method "POST" -Headers (Get-DeeplAuthorizationHeader) -Uri "https://api-free.deepl.com/v2/usage"
	return $result.character_limit - $result.character_count
}

# Translation using https://www.deepl.com/
function Get-DeeplTranslation {
	param (
		$text,
		$selectedFrom,
		$selectedTo,
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

	$remainingChars = Get-DeeplRemainingCharacters
	if ($remainingChars -lt $text.Length) {
		WriteMessage -failure "There are not enough credits left to translate, $remainingChars left and text is $($text.Length) characters"
		return
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
			$answer = Read-Host "Select FROM language (empty is auto)"
			if ($answer) {
				$selectedFrom = $shorts[$answer - 1]
			} else {
				$selectedFrom = "AUTO"
			}
			for ($i = 0; $i -lt $languages.Count; $i++) {
				Write-Host "$($i + 1): $($languages[$i])"
			}
			$answer = Read-Host "Select TO language (REQUIRED)"
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
	$urlSuffix += "&text=$text"

	WriteMessage -progress "Translating '$text' from $selectedFrom to $selectedTo"

	$result = Invoke-RestMethod -Method "POST" -Headers (Get-DeeplAuthorizationHeader) -Uri "https://api-free.deepl.com/v2/translate$urlSuffix"

	return $result.translations.text
}

# Depricated
# Generates default language files for english
# Uses rimtrans from https://github.com/Aironsoft/RimTrans
function Set-Translation {
	param (
		[string] $modName,
		[switch] $force
	)

	WriteMessage -failure "RimTrans is not working at the moment"
	return

	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}
	
	if (-not (Get-OwnerIsMeStatus -modName $modName) -and -not $force) {
		WriteMessage -failure "$modName is not mine, aborting update"
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

	(Get-Content $rimTransTemplate -Raw -Encoding UTF8).Replace("[modpath]", "$localModFolder\$modName") | Out-File $currentFile -Encoding utf8
	
	$process = Start-Process -FilePath $rimTransExe -ArgumentList $command -PassThru 
	Start-Sleep -Seconds 1
	$wshell = New-Object -ComObject wscript.shell;
	$wshell.AppActivate('RimTrans')
	$wshell.SendKeys('{ENTER}')
	while (-not $process.HasExited) {
		Start-Sleep -Milliseconds 200 
	}
	WriteMessage -success "Generation done"	
	Remove-Item -Path $currentFile -Force
}

#endregion

#region Trello functions
function Get-TrelloBoards {
	$boards = Invoke-RestMethod -Uri "https://api.trello.com/1/members/me/boards?key=$trelloKey&token=$trelloToken" -Verbose:$false
	return $boards
}

function Get-TrelloCards {
	param($boardId)
	if (-not $boardId) {
		$boardId = $trelloBoardId
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

function Add-TrelloCardComment {
	param($cardId, $comment)
	$comment = [uri]::EscapeDataString($comment)
	Invoke-RestMethod -Method Post -Uri "https://api.trello.com/1/cards/$($cardId)/actions/comments?key=$trelloKey&token=$trelloToken&text=$comment" -Verbose:$false | Out-Null
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
	param ($text, $fieldId)
	$cards = Get-TrelloCards -boardId $trelloBoardId
	$cards | ForEach-Object { if ($_.customFieldItems -and $_.customFieldItems.idCustomField.contains($fieldId)) {
			if ($text -eq ($_.customFieldItems | Where-Object { $_.idCustomField -eq $fieldId }).value.text) {
				return $_ 
			} 
		} 
	}
}

function Get-TrelloCardsForMod {
	param($modName)
	
	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}

	$publishedFileId = "$localModFolder\$modname\About\PublishedFileId.txt"

	if (-not (Test-Path $publishedFileId)) {
		WriteMessage -warning "No PublishedFileId.txt found at $publishedFileId"
		return
	}

	$modId = Get-Content -Path $publishedFileId -Encoding utf8
	if (-not $modId) {
		WriteMessage -warning "$publishedFileId contains no modid"
		return
	}

	return (Find-TrelloCardByCustomField -text "https://steamcommunity.com/sharedfiles/filedetails/?id=$modId" -fieldId $trelloLinkId)
}

function Close-TrelloCardsForMod {
	param($modName)

	if (-not $modName) {
		$modName = Get-CurrentModNameFromLocation
		if (-not $modName) {
			return
		}
	}

	$foundCards = Get-TrelloCardsForMod -modName $modName

	if (-not $foundCards) {
		WriteMessage -progress "No active Trello cards found for mod"
		return
	}

	WriteMessage -progress "Found $($foundCards.Count) active Trello cards for $modName"
	$counter = 1
	foreach ($card in $foundCards) {
		Write-Host -ForegroundColor Green "`n$counter - $($card.name) ( $($card.shortUrl) )`n$($card.desc)`n"
		$counter++
	}

	$selection = Read-Host "What card(s) do you want to close, select multiple separated by space"
	if (-not $selection) {
		WriteMessage -progress "No card chosen"
		return
	}

	foreach ($choice in $selection.Split(" ")) {
		$card = $foundCards[$choice - 1]
		WriteMessage -progress "Closing $($choice) - $($card.name) ($($card.dateLastActivity))"
		Set-TrelloCardToArchived -cardId $card.id
	}
}

#endregion