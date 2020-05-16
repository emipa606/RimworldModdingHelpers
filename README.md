# RimworldModdingHelpers

My modding helpers in my work for updating and supporting RimWorld mods.

The PowerShell-functions in the module has descriptions describing the process but here is a general description.

Since I update a lot of old mods I needed a way to steamline the xml-updating and github-publishing.
This evolved into more and more functions that later became a separate module.

The two main functions are the xml-updating function and the github-publishing function.

- The first goes through all xml and replaces/removes old values/properties/strings. This can otherwise be a slow and repetative process when updating old mods. It does not fix everything of course but removes 70-90% of the time consumed.

- The second function updates the mod-version and all relevant files and then pushes the new version of the mod to a git-hub repo. If the repo does not exist it creates it. It also creates a new release of the mod with the new version.

Other than that there are a couple of quality of life-functions:
- Language-file creation, with help of RimTrans (https://github.com/RimWorld-zh/RimTrans/releases/latest)
- Texture-renaming from the old front/back/side to the new south/north/east
- Quickly loading the mod-page in a browser
- Starting RimWorld, either for playing or modding with separate modlists and settings
- Get the latest version of a mod from a github-repo for fetching non-steam mods
