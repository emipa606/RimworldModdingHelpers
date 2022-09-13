from bs4 import BeautifulSoup
from urllib.request import urlopen
import os.path
from pathlib import Path
import time
from discord_webhook import DiscordWebhook, DiscordEmbed
from datetime import datetime as datetimesub, timedelta
from dateutil.parser import parser
import os
import glob
import sys
import re
import uuid
import json
import sys

test = False
if (len(sys.argv) > 1):
    test = True


def read_json(file_path):
    with open(file_path, "r", encoding="utf-8") as f:
        return json.load(f)


config_path = Path(
    f"{os.path.dirname(os.path.realpath(__file__))}/workshop_scraper.json")
if (not os.path.isfile(config_path)):
    print(f"No config-file found: {config_path}, create and try again")
    sys.exit()

settings = read_json(config_path)
newDiscord = settings["discord_new_mods_channel"]
updatedDiscord = settings["discord_updated_mods_channel"]

if (test):
    newDiscord = settings["discord_test_channel"]
    updatedDiscord = settings["discord_test_channel"]

newModsUrl = settings["steam_new_mods_search_url"]
updatedModsUrl = settings["steam_updated_mods_search_url"]
updatedModsUrl = updatedModsUrl + \
    str(int((datetimesub.now() - timedelta(minutes=10)).timestamp()))
currentDigest = datetimesub.now().hour

cachePath = settings["caching_folder"]
digestTitle = settings["digest_title"]
maxPostsPerHour = settings["discord_posts_per_hour"]
steamWorkshopPath = settings["steam_workshop_path"]

digestPath = f"{cachePath}/digest"
updatedPath = f"{cachePath}/updated"
newPath = f"{cachePath}/new"
embedsPath = f"{cachePath}/embeds"
embedsUpdatedPath = f"{embedsPath}/updated"
embedsNewPath = f"{embedsPath}/new"

if not os.path.exists(Path(digestPath)):
    os.makedirs(Path(digestPath))
if not os.path.exists(Path(updatedPath)):
    os.makedirs(Path(updatedPath))
if not os.path.exists(Path(newPath)):
    os.makedirs(Path(newPath))
if not os.path.exists(Path(embedsUpdatedPath)):
    os.makedirs(Path(embedsUpdatedPath))
if not os.path.exists(Path(embedsNewPath)):
    os.makedirs(Path(embedsNewPath))
onlyLocal = steamWorkshopPath and os.path.exists(Path(steamWorkshopPath))


def postOldDigest(webhookurl):
    lastDigest = (datetimesub.now() - timedelta(hours=1)).hour
    fileName = Path(f'{digestPath}/{lastDigest}')
    if (os.path.isfile(fileName)):
        with open(fileName, 'r', encoding="utf-8") as the_file:
            lines = the_file.readlines()
        description = ""
        count = 0
        for line in lines:
            lineSplitted = line.split('|')
            if (len(lineSplitted) != 3):
                continue
            count = count + 1
            description = description + \
                f"[{lineSplitted[0]}]({lineSplitted[2]}) {lineSplitted[1]}\n"
        embed = DiscordEmbed(title=digestTitle)
        embed.add_embed_field(
            name=f"{count} mods", value=description.rstrip(), inline=True)
        webhook = DiscordWebhook(url=webhookurl)
        webhook.add_embed(embed)
        response = webhook.execute()
        os.remove(fileName)


def postDiscordMessages(url, updated):
    lastHour = (datetimesub.now() - timedelta(hours=1)).hour
    thisHour = (datetimesub.now()).hour
    if updated:
        oldName = Path(f'{embedsPath}/update{lastHour}')
        currentName = Path(f'{embedsPath}/update{thisHour}')
        path = Path(embedsUpdatedPath)
    else:
        oldName = Path(f'{embedsPath}/new{lastHour}')
        currentName = Path(f'{embedsPath}/new{thisHour}')
        path = Path(embedsNewPath)
    if os.path.isfile(oldName):
        os.remove(oldName)
    if (not os.path.isfile(currentName)):
        Path(currentName).touch()
        with open(currentName, 'a', encoding="utf-8") as the_file:
            the_file.write('0')
    with open(currentName, 'r', encoding="utf-8") as the_file:
        currentPosts = int(the_file.read())
    files = list(filter(os.path.isfile, path.glob('*')))
    files.sort(key=lambda x: os.path.getmtime(x))
    for file in files:
        if currentPosts > maxPostsPerHour:
            break
        sendEmbed(file, url)
        currentPosts = currentPosts + 1
    with open(currentName, 'w', encoding="utf-8") as the_file:
        the_file.write(f'{currentPosts}')


def saveToDigest(title, author, link):
    fileName = Path(f'{digestPath}/{currentDigest}')
    if (not os.path.isfile(fileName)):
        Path(fileName).touch()
    with open(fileName, 'a', encoding="utf-8") as the_file:
        the_file.write(f'{title}|{author}|{link}\n')


def saveEmbed(embed, folder):
    tempname = str(uuid.uuid4())
    fileName = f'{embedsPath}/{folder}/{tempname}'
    Path(fileName).touch()
    data = {'title': embed.title, 'url': embed.url, 'author': {
        'name': embed.author['name'], 'url': embed.author['url'], 'icon_url': embed.author['icon_url']}, 'description': embed.description, 'thumbnail': embed.thumbnail['url']}
    text = json.dumps(data)
    with open(fileName, 'a', encoding="utf-8") as the_file:
        the_file.write(text)


def sendEmbed(filepath, url):
    with open(filepath, 'r', encoding="utf-8") as the_file:
        embedText = the_file.read()
    embedJson = json.loads(embedText)
    embed = DiscordEmbed(title=embedJson['title'], url=embedJson['url'])
    embed.set_author(name=embedJson['author']['name'], url=embedJson['author']
                     ['url'], icon_url=embedJson['author']['icon_url'])
    embed.description = embedJson['description']
    embed.set_thumbnail(url=embedJson['thumbnail'])
    webhook = DiscordWebhook(url=url)
    webhook.add_embed(embed)
    response = webhook.execute()
    print(response)
    os.remove(filepath)
    time.sleep(1)


def htmlToDiscord(message):
    linkFilter = '<a.*(?:href=")(?P<link>[^"]*)[^>]*>(?P<text>[^<]*)<\/a>'
    headerFilter = '<div class="bb_h.">(?P<text>.*)<\/div>'
    authorFilter = '<div class="bb_quoteauthor">(?P<text>.*)<\/div>'
    autogenFilter = '\[Auto\-generated text\].*\.'
    imageFilter = '<img.*src="(?P<link>.*)"*.>'
    externalLinkFilter = '<span class="bb_link_host">.*<\/span>'
    myInfo = '<img src="https://i.imgur.com/pufA0kM.png">.*<img src="https://i.imgur.com/Z4GOv8H.png">'
    myFooter = '<img src="https://i.imgur.com/PwoNOj4.png">.*'
    message = re.sub(myInfo, r'```\nOriginal Description\n```', message)
    message = re.sub(myFooter, r'', message)
    message = message.replace(
        '<img src="https://i.imgur.com/buuPQel.png">', '')
    message = message.replace('<br/><br/><br/>', '<br/><br/>')
    message = message.replace('<br/>', '\n').replace('\\n', '\n')
    message = message.replace('<i>', '*').replace('</i>', '*')
    message = message.replace('<b>', '**').replace('</b>', '**')
    message = message.replace('<u>', '__').replace('</u>', '__')
    message = message.replace('<s>', '~~').replace('</s>', '~~')
    message = message.replace('<li>', '* ').replace('</li>', '')
    message = message.replace(
        '⦿', '*').replace('•', '*').replace('https://steamcommunity.com/linkfilter/?url=', '')
    message = message.replace('target="_blank"', '').replace(
        'rel="noreferrer"', '').replace('class="bb_link"', '')
    message = message.replace('<ul>', '').replace(
        '<ul class="bb_ul">', '').replace('</ul>', '')
    message = message.replace('</img>', '').replace('&amp;', '&')
    message = message.replace('&lt;', '<').replace('&gt;', '>')
    message = message.replace(
        '<blockquote class="bb_blockquote with_author">', '>>> ')
    message = message.replace('</blockquote>', '')
    message = re.sub(linkFilter, r'[\g<text>](\g<link>)', message)
    message = re.sub(headerFilter, r'> \g<text>\n', message)
    message = re.sub(authorFilter, r'\[\g<text>\]\n', message)
    message = re.sub(imageFilter, r'\g<link>', message)
    message = re.sub(externalLinkFilter, '', message)
    message = re.sub(autogenFilter, '', message)
    message = message.replace('</div>', '').replace('</di', '')
    if (len(message) > 4000):
        message = message[0:4000]
    return message


def generateDiscordPost(each_div, script, webhookurl, updated):
    link = each_div.findAll("a", {"class": "ugc"})[0]['href'].split('&')[0]
    wid = link.split('=')[1]
    description = ""
    if updated:
        if onlyLocal and not os.path.isfile(Path(f'{steamWorkshopPath}/' + wid + '/About/About.xml')):
            print(wid + " is not subscribed, ignoring")
            return
        changelogPage = urlopen(
            "https://steamcommunity.com/sharedfiles/filedetails/changelog/" + wid)
        changelogData = changelogPage.read().decode("utf-8")
        changelogSoup = BeautifulSoup(changelogData, "html.parser")
        datetag = changelogSoup.find("div", {"class": "workshopAnnouncement"}).find(
            "div", {"class": "changelog"}).text.strip().replace("Update: ", "")
        firstPart = datetag.split('@')[0].strip()
        if (firstPart.count(',') == 0):
            firstPart = firstPart + " " + str(datetimesub.now().year)
        lastPart = datetag.split('@')[-1].strip()
        lastUpdatedString = firstPart + " " + lastPart
        date_parser = parser()
        lastUpdated = str(date_parser.parse(lastUpdatedString).timestamp())
        if not test and os.path.isfile(Path(f'{updatedPath}/' + wid + lastUpdated)):
            print(wid + " is already reported, ignoring")
            return
    else:
        if not test and os.path.isfile(Path(f'{newPath}/' + wid)):
            print(wid + " is already reported, ignoring")
            return
    title = each_div.findAll(
        "div", {"class": "workshopItemTitle ellipsis"})[0].text
    image = each_div.findAll(
        "img", {"class": "workshopItemPreviewImage aspectratio_16x9"})[0]['src']
    authorName = each_div.findAll(
        "div", {"class": "workshopItemAuthorName ellipsis"})[0].find("a").text
    modPage = urlopen(
        "https://steamcommunity.com/sharedfiles/filedetails/" + wid)
    modData = modPage.read().decode("utf-8")
    modSoup = BeautifulSoup(modData, "html.parser")
    authorImage = modSoup.findAll("div", {"class": "playerAvatar"})[
        0].find("img").attrs['src']
    authorPage = modSoup.findAll("a", class_="friendBlockLinkOverlay")[
        0].attrs['href']
    embed = DiscordEmbed(title=title, url=link)
    embed.set_author(name=authorName, url=authorPage, icon_url=authorImage)
    if updated:
        description = htmlToDiscord(
            changelogSoup.find("p").encode_contents().decode())
        if len(description) > 0:
            description = f"**Changenote**\n{description}"
            embed.description = description
        else:
            if not test:
                saveToDigest(title, authorName, link)
                Path(f'{updatedPath}/' + wid + lastUpdated).touch()
            else:
                print(wid + " has no changelog, would add to digest instead")
            return
    else:
        description = htmlToDiscord(modSoup.find(
            "div", {"class": "workshopItemDescription"}).encode_contents().decode())
        if len(description) > 0:
            embed.description = description
    embed.set_thumbnail(url=image)

    if updated:
        saveEmbed(embed, "updated")
        if not test:
            Path(f'{updatedPath}/' + wid + lastUpdated).touch()
    else:
        saveEmbed(embed, "new")
        if not test:
            Path(f'{newPath}/' + wid).touch()


postOldDigest(updatedDiscord)

page = urlopen(newModsUrl)
htmldata = page.read().decode("utf-8")
soup = BeautifulSoup(htmldata, "html.parser")
pattern = re.compile('description":"[^"]+"', re.MULTILINE)
workshopItems = soup.findAll("div", {"class": "workshopItem"})
scripts = soup.findAll("script", text=pattern)
print(f"{len(workshopItems)} workshop items, {len(scripts)} scripts")
for i in range(len(workshopItems) - 1):
    if (test and i >= 10):
        print(f"Only testing, will only print {i}")
        break
    print(f"Parsing new item {i}")
    generateDiscordPost(workshopItems[i], scripts[i], newDiscord, False)
postDiscordMessages(newDiscord, False)

page = urlopen(updatedModsUrl)
htmldata = page.read().decode("utf-8")
soup = BeautifulSoup(htmldata, "html.parser")
pattern = re.compile('description":"[^"]+"', re.MULTILINE)
workshopItems = soup.findAll("div", {"class": "workshopItem"})
scripts = soup.findAll("script", text=pattern)
print(f"{len(workshopItems)} workshop items, {len(scripts)} scripts")
for i in range(len(workshopItems) - 1):
    if (test and i >= 10):
        print(f"Only testing, will only print {i}")
        break
    print(f"Parsing updated item {i}")
    generateDiscordPost(workshopItems[i], scripts[i], updatedDiscord, True)
postDiscordMessages(updatedDiscord, True)
