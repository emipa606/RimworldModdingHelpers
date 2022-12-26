"""Scrapes steam for comments

Returns:
_type_: _description_
"""
import sys
import time
import os
import json
import re
import steam.webauth as wa
import requests
from bs4 import BeautifulSoup
from discord_webhook import DiscordWebhook, DiscordEmbed

if len(sys.argv) < 2:
    print('Must supply a twofactor-code')
    exit()

CONFIG_PATH = "./comment_scraper.json"
if not os.path.isfile(CONFIG_PATH):
    print(f"No config-file found: {CONFIG_PATH}, create and try again")
    sys.exit()


def read_json(file_path):
    """Reads json file"""
    with open(file_path, "r", encoding="utf8") as file:
        return json.load(file)


settings = read_json(CONFIG_PATH)
webhookUrl = settings["discord_channel"]
infoWebhookUrl = settings["discord_test_channel"]
displayname = settings["steam_displayname"]
username = settings["steam_username"]
password = settings["steam_password"]
timestampfile = settings["timestamp_filename"]
timestampfilePath = f"./{timestampfile}"

TESTING = False
if len(sys.argv) == 3:
    TESTING = True

if not os.path.isfile(timestampfilePath):
    with open(timestampfile, 'w', encoding="utf8") as f:
        f.write('')


def sendlogpost(title, logtext):
    """Sends message to the log-channel"""
    logtext = htmltodiscord(logtext)
    embed = DiscordEmbed(title=title)
    embed.description = logtext
    webhook = DiscordWebhook(url=infoWebhookUrl)
    webhook.add_embed(embed)
    webhook.execute()


def senddiscordpost(modurl, modtitle, authorname, authorpagelink, authorimage, messagetext, testing):
    """Sends message to the real channel"""
    messagetext = htmltodiscord(messagetext)
    embed = DiscordEmbed(title=modtitle, url=modurl)
    embed.set_author(name=authorname, url=authorpagelink, icon_url=authorimage)
    embed.description = messagetext
    if testing:
        webhook = DiscordWebhook(url=infoWebhookUrl)
    else:
        webhook = DiscordWebhook(url=webhookUrl)
    webhook.add_embed(embed)
    webhook.execute()


def htmltodiscord(message):
    """Converts html-code to discord-friendly code"""
    linkfilter = r'<a.*(?:href=")(?P<link>[^"]*)[^>]*>(?P<text>[^<]*)<\/a>'
    imagefilter = r'<img.*src="(?P<link>.*)"*.>'
    externallinkfilter = r'<span class="bb_link_host">.*<\/span>'
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
    message = message.replace('</div>', '').replace('</di', '')
    message = re.sub(linkfilter, r'[\g<text>](\g<link>)', message)
    message = re.sub(imagefilter, r'\g<link>', message)
    message = re.sub(externallinkfilter, '', message)
    if len(message) > 4000:
        message = message[0:4000]
    return message


if TESTING:
    sendlogpost("Starting comment monitor", "Running in test-mode")
user = wa.WebAuth(username)
TWOFACTORCODE = sys.argv[1]
if TESTING:
    sendlogpost("Comment monitor", f"Logging in with code {TWOFACTORCODE}")

tryagain = False
try:
    result = user.login(password=password, twofactor_code=TWOFACTORCODE)
except Exception as e:
    if TESTING:
        sendlogpost("Comment monitor", "Failed, trying to log in again")
    tryagain = True
if tryagain:
    try:
        result = user.login(password=password, twofactor_code=TWOFACTORCODE)
    except Exception as e:
        sendlogpost("Comment monitor login failed", str(e))

try:
    if TESTING:
        sendlogpost("Comment monitor", f"Login result: {result}")

    while user.session.verify:
        currentNotifications = user.session.get(
            f'https://steamcommunity.com/id/{displayname}/commentnotifications/').text
        soup = BeautifulSoup(currentNotifications, 'html.parser')

        LASTHIGHESTTIMESTAMP = 0
        with open(timestampfile, "r", encoding="utf8") as f:
            fileContent = f.read()
            if fileContent:
                LASTHIGHESTTIMESTAMP = int(fileContent)
        NEWHIGHESTTIMESTAMP = LASTHIGHESTTIMESTAMP

        notificationsDiv = soup.find(
            "div", {"class": "commentnotifications_header_commentcount"})
        if not notificationsDiv and not TESTING:
            print('No new notifications')
            time.sleep(60)
            continue

        if notificationsDiv:
            archiveMode = False
            if TESTING:
                sendlogpost("Comment monitor",
                            f"Found {notificationsDiv.text} new notifications")
            print(f'Found {notificationsDiv.text} new notifications')

            unreadNotifications = soup.findAll(
                "div", {"class": "commentnotification unread"})[::-1]
        else:
            archiveMode = True
            sendlogpost("Comment monitor",
                        "No new notifications, using the last 5 for testing")
            unreadNotifications = soup.findAll(
                "div", {"class": "commentnotification"})[:5]

        for notification in unreadNotifications:
            link = (notification.find("a")['href']).split('&')[0]
            if TESTING:
                linkPage = requests.get(link, timeout=10).text
            else:
                linkPage = user.session.get(link).text
            linkSoup = BeautifulSoup(linkPage, 'html.parser')

            if "discussion" in link:
                modName = linkSoup.find(
                    "div", {"class": "topic"}).text.strip()
            elif linkSoup.find("div", {"class": "screenshotApp"}):
                modName = "Screenshot comment"
            else:
                modName = linkSoup.find(
                    "div", {"class": "workshopItemTitle"}).text.strip()
            allComments = linkSoup.findAll(
                "div", {"class": "commentthread_comment"})[::-1]
            if len(allComments) == 0:
                link = f"https://steamcommunity.com/sharedfiles/filedetails/comments/{link.split('=')[1]}"
                if TESTING:
                    linkPage = requests.get(link, timeout=5).text
                else:
                    linkPage = user.session.get(link).text
                linkSoup = BeautifulSoup(linkPage, 'html.parser')
                allComments = linkSoup.findAll(
                    "div", {"class": "commentthread_comment"})
            mainStamp = int(notification.find(
                "div", {"class": "commentnotification_date"}).find("span")['data-timestamp'])
            NEWHIGHESTTIMESTAMP = mainStamp
            if LASTHIGHESTTIMESTAMP == 0:
                LASTHIGHESTTIMESTAMP = mainStamp - 1

            if TESTING:
                sendlogpost("Comment monitor",
                            f"{modName}: {mainStamp}")
            ignored = []

            if archiveMode:
                allComments = [allComments[-1]]

            for comment in allComments:
                commentStamp = comment.find(
                    "span", {"class": "commentthread_comment_timestamp"})['data-timestamp']
                if not archiveMode and LASTHIGHESTTIMESTAMP >= int(commentStamp):
                    ignored.append(commentStamp)
                    continue
                author = comment.find(
                    "a", {"class": "commentthread_author_link"}).text.split("(")[0].strip()
                authorPage = comment.find("a").attrs['href']
                imageUrl = comment.find("img")['src']
                textDiv = comment.find(
                    "div", {"class": "commentthread_comment_text"})
                TEXT = ""
                for textBit in textDiv.contents:
                    if str(textBit) == "<br/>":
                        TEXT = TEXT + "\n"
                    else:
                        TEXT = TEXT + str(textBit).strip()
                if TESTING:
                    senddiscordpost(link, modName, author,
                                    authorPage, imageUrl, TEXT, True)
                else:
                    senddiscordpost(link, modName, author,
                                    authorPage, imageUrl, TEXT, False)

            if not archiveMode and TESTING:
                sendlogpost(
                    "Comment monitor", f"Sent {len(allComments) - len(ignored)} comments for {modName} \n{ ','.join(ignored) }")

        if TESTING:
            sendlogpost("Testrun complete", "Script exited")
            exit()
        with open(timestampfile, 'w', encoding="utf8") as f:
            f.write(str(NEWHIGHESTTIMESTAMP))
        time.sleep(60)

    sendlogpost("Comment monitor down", "No longer authorized")
except Exception as e:
    sendlogpost("Comment monitor failed", str(e))
