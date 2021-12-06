# RimWorld Collection Manager

## What does this program do?
This tool can be used to update mod-collections based on save-games

Call the exe with the following parameters:

Parameter 1:
The collection id you want to work on

Parameter 2:
The path to the save-game you want to add the mods from. Remember to add "" around the path if it contains spaces.
This parameter can also be a mod-id, in witch case it will just add that mod-id to the collection.

The tool will then fetch all current items in the collection
It will then remove all but one, as a collection must have at least one item
It will then add the mods in the save-game and also ofc removing the left mod from the last step

Depending on the amount of mods this can take a while