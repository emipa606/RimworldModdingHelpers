# RimWorld Description Edit

## What does this program do?
This tool can be used to interract with the description of a workshop item

Call the exe with the following parameters:

Parameter 1:
The workshop id you want to interract with
If this is the only parameter given, will return the title and description of the item

Parameter 2:
Optional operation to do on the description, valid values are
REPLACE
SET
SYNC
SAVE
GET
UPDATE

Description of operations:
REPLACE
Searches for a string in the description (parameter 3) and replaces it with a new string (parameter 4). 

SET
Sets the description to the content of the file at the given path (parameter 3)

SYNC
Not implemented yet

SAVE
Saves the description to a file at the given path (parameter 3)

GET
Used to get various other properties of the mod-page, currently AUTHOR given as argument 3 is implemented

UPDATE
Used to update other properties of the mod-page, currently PREVIEW as a path to an image-file given as argument 3 is implemented