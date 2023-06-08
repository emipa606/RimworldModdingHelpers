"""Validates preview images

Returns:
_type_: _description_
"""
import sys
import os
import json
import pathlib
import steam.webauth as wa
from bs4 import BeautifulSoup
import PIL.Image as Image
import webbrowser
import pyperclip

if len(sys.argv) < 2:
    TWOFACTORCODE = input('Must supply a twofactor-code:')
else:
    TWOFACTORCODE = sys.argv[1]

CONFIG_PATH = "./preview_validator.json"
if not os.path.isfile(CONFIG_PATH):
    print(f"No config-file found: {CONFIG_PATH}, create and try again")
    sys.exit()


def read_json(file_path):
    """Reads json file"""
    with open(file_path, "r", encoding="utf8") as file:
        return json.load(file)


modsfolder = pathlib.Path("E:\SteamLibrary\steamapps\common\RimWorld\Mods")
allpublishedfiles = list(modsfolder.glob("*/About/PublishedFileId.txt"))
settings = read_json(CONFIG_PATH)
prefix = settings["modid_prefix"]
username = settings["steam_username"]
password = settings["steam_password"]

user = wa.WebAuth(username)
print(f"Logging in with code {TWOFACTORCODE}")

tryagain = False
try:
    result = user.login(password=password, twofactor_code=TWOFACTORCODE)
except Exception as e:
    print(f"Comment monitor login failed", str(e))
    sys.exit()

try:
    print(f"Login result: {result}")

    for publishfile in allpublishedfiles:
        modname = os.path.basename(os.path.split(
            os.path.split(publishfile)[0])[0])
        print(f"Checking {modname}")
        sourcepath = os.path.join(os.path.split(
            os.path.split(publishfile)[0])[0], "source")
        aboutpath = os.path.join(os.path.split(publishfile)[0], "About.xml")
        with open(aboutpath, mode="r", encoding="utf-8") as f:
            if f'<packageId>{prefix}.' not in f.read():
                print(f"Skipping {modname} as its not my mod")
                continue
        with open(publishfile, 'r') as f:
            id = f.read()
        uri = f'https://steamcommunity.com/sharedfiles/managepreviews/?id={id}'
        previewpage = user.session.get(uri)
        soup = BeautifulSoup(previewpage.text, 'html.parser')
        allscripts = soup.find_all('script', type="text/javascript")
        previewscript = list(
            filter(lambda a: 'gPreviewImages' in a.text, allscripts))[0].text
        previews = previewscript.split('[')[1].split(']')[0]
        jsonlist = json.loads(f"[{previews}]")
        for preview in jsonlist:
            if preview['size'] > 0:
                continue
            filepath = os.path.join(sourcepath, preview['filename'])
            tmppath = os.path.join(sourcepath, f"{preview['filename']}.bak")
            print(f"{modname} broken preview: {preview['filename']}")
            if os.path.isfile(filepath):
                os.rename(filepath, tmppath)
                img = Image.open(tmppath)
                img.save(filepath, optimize=True, quality=60)
                os.remove(tmppath)
                pyperclip.copy(filepath.replace('\\\\', '\\'))

            webbrowser.open(uri, new=0, autoraise=True)
            input('Continue?')

except Exception as e:
    print("Session failed", str(e))
