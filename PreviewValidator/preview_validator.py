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
from wand.image import Image
import pyperclip
import subprocess

CONFIG_PATH = "./preview_validator.json"
if not os.path.isfile(CONFIG_PATH):
    print(f"No config-file found: {CONFIG_PATH}, create and try again")
    sys.exit()


def read_json(file_path):
    """Reads json file"""
    with open(file_path, "r", encoding="utf8") as file:
        return json.load(file)


modsfolder = pathlib.Path(r"E:\SteamLibrary\steamapps\common\RimWorld\Mods")
previewExecutable = r"E:\ModPublishing\PowershellFunctions\SteamPreviewUploader\Compiled\SteamPreviewUploader.exe"
allpublishedfiles = list(modsfolder.glob("*/About/PublishedFileId.txt"))
settings = read_json(CONFIG_PATH)
prefix = settings["modid_prefix"]
username = settings["steam_username"]
password = settings["steam_password"]

user = wa.WebAuth2(username)

# If there is no two-factor code supplied as argument, prompt for it
if len(sys.argv) < 2:
    twoFactorCode = input(
        "Logging in, paste two-factor code and press enter: ")
else:
    twoFactorCode = sys.argv[1]

tryagain = False
try:
    result = user.login(username, password, twoFactorCode)
except Exception as e:
    print("Comment monitor login failed", str(e))
    sys.exit()

try:
    print(f"Login result: {result}")

    for publishfile in allpublishedfiles:
        modpath = os.path.split(os.path.split(publishfile)[0])[0]
        modname = os.path.basename(modpath)
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
        if not jsonlist:
            print(f"Skipping {modname} since it has no previews")
            continue
        for preview in jsonlist:
            if preview['size'] > 0:
                continue
            # print(preview)
            filepath = os.path.join(sourcepath, preview['filename'])
            tmppath = os.path.join(sourcepath, f"{preview['filename']}.bak")
            print(f"{modname} broken preview: {preview['filename']}")
            if os.path.isfile(filepath):
                with Image(filename=filepath) as img:
                    img.save(filename=filepath)
                pyperclip.copy(filepath.replace('\\\\', '\\'))

            index = preview["sortorder"] - 1
            previewpath = filepath.replace('\\\\', '\\')
            callstring = f'"{previewExecutable}" "{modpath}" "{previewpath}" "{index}"'
            # print(callstring)
            subprocess.call(callstring)
            # webbrowser.open(uri, new=0, autoraise=True)
            # input('Continue?')

except Exception as e:
    print("Session failed", str(e))
