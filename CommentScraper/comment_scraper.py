import sys
import time
import os
import json
import re
import steam.webauth as wa
import requests
from bs4 import BeautifulSoup
from discord_webhook import DiscordWebhook, DiscordEmbed

if (len(sys.argv) < 2):
    print('Must supply a twofactor-code')
    exit()

config_path = "./comment_scraper.json"
if (not os.path.isfile(config_path)):
    print(f"No config-file found: {config_path}, create and try again")
    sys.exit()


def read_json(file_path):
    with open(file_path, "r") as f:
        return json.load(f)


settings = read_json(config_path)
webhookUrl = settings["discord_channel"]
infoWebhookUrl = settings["discord_test_channel"]
displayname = settings["steam_displayname"]
username = settings["steam_username"]
password = settings["steam_password"]
timestampfile = settings["timestamp_filename"]
timestampfilePath = f"./{timestampfile}"

testing = False
if (len(sys.argv) == 3):
    testing = True

if (not os.path.isfile(timestampfilePath)):
    with open(timestampfile, 'w') as f:
        f.write('')


def sendLogPost(title, text):
    text = htmlToDiscord(text)
    embed = DiscordEmbed(title=title)
    embed.description = text
    webhook = DiscordWebhook(url=infoWebhookUrl)
    webhook.add_embed(embed)
    webhook.execute()


def sendDiscordPost(modUrl, modName, authorName, authorPage, authorImage, text):
    text = htmlToDiscord(text)
    embed = DiscordEmbed(title=modName, url=modUrl)
    embed.set_author(name=authorName, url=authorPage, icon_url=authorImage)
    embed.description = text
    webhook = DiscordWebhook(url=webhookUrl)
    webhook.add_embed(embed)
    webhook.execute()


def htmlToDiscord(message):
    linkFilter = '<a.*(?:href=")(?P<link>[^"]*)[^>]*>(?P<text>[^<]*)<\/a>'
    imageFilter = '<img.*src="(?P<link>.*)"*.>'
    externalLinkFilter = '<span class="bb_link_host">.*<\/span>'
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
    message = re.sub(linkFilter, r'[\g<text>](\g<link>)', message)
    message = re.sub(imageFilter, r'\g<link>', message)
    message = re.sub(externalLinkFilter, '', message)
    if (len(message) > 4000):
        message = message[0:4000]
    return message


if (testing):
    sendLogPost("Starting comment monitor", "Running in test-mode")
try:
    user = wa.WebAuth(username)
    twoFactorCode = sys.argv[1]
    if (testing):
        sendLogPost("Comment monitor", f"Logging in with code {twoFactorCode}")
    result = user.cli_login(password=password, twofactor_code=twoFactorCode)

    if (testing):
        sendLogPost("Comment monitor", f"Login result: {result}")

    while (user.session.verify):
        currentNotifications = user.session.get(
            f'https://steamcommunity.com/id/{displayname}/commentnotifications/').text
        soup = BeautifulSoup(currentNotifications, 'html.parser')

        lastHighestTimestamp = 0
        with open(timestampfile, "r") as f:
            fileContent = f.read()
            if (fileContent):
                lastHighestTimestamp = int(fileContent)
        newHighestTimestamp = lastHighestTimestamp

        notificationsDiv = soup.find(
            "div", {"class": "commentnotifications_header_commentcount"})

        if (not notificationsDiv):
            if (testing):
                sendLogPost("Comment monitor", "No new notifications")
            print('No new notifications')
        else:
            if (testing):
                sendLogPost("Comment monitor",
                            f"Found {notificationsDiv.text} new notifications")
            print(f'Found {notificationsDiv.text} new notifications')

            unreadNotifications = soup.findAll(
                "div", {"class": "commentnotification unread"})[::-1]

            for notification in unreadNotifications:
                link = (notification.find("a")['href']).split('&')[0]
                if (testing):
                    linkPage = requests.get(link).text
                else:
                    linkPage = user.session.get(link).text
                linkSoup = BeautifulSoup(linkPage, 'html.parser')
                modName = linkSoup.find(
                    "div", {"class": "workshopItemTitle"}).text.strip()
                allComments = linkSoup.findAll(
                    "div", {"class": "commentthread_comment"})[::-1]
                mainStamp = int(notification.find(
                    "div", {"class": "commentnotification_date"}).find("span")['data-timestamp'])
                newHighestTimestamp = mainStamp
                if (lastHighestTimestamp == 0):
                    lastHighestTimestamp = mainStamp - 1

                if (testing):
                    sendLogPost("Comment monitor",
                                f"{modName}: {mainStamp}")
                ignored = []
                for comment in allComments:
                    commentStamp = comment.find(
                        "span", {"class": "commentthread_comment_timestamp"})['data-timestamp']
                    if (lastHighestTimestamp >= int(commentStamp)):
                        ignored.append(commentStamp)
                        continue
                    author = comment.find(
                        "a", {"class": "commentthread_author_link"}).text.split("(")[0].strip()
                    authorPage = comment.find("a").attrs['href']
                    imageUrl = comment.find("img")['src']
                    textDiv = comment.find(
                        "div", {"class": "commentthread_comment_text"})
                    text = ""
                    for textBit in textDiv.contents:
                        if (str(textBit) == "<br/>"):
                            text = text + "\n"
                        else:
                            text = text + str(textBit).strip()
                    if (testing):
                        sendLogPost(modName, text)
                    else:
                        sendDiscordPost(link, modName, author,
                                        authorPage, imageUrl, text)

                if (testing):
                    sendLogPost("Comment monitor",
                                f"Sent {len(allComments) - len(ignored)} comments for {modName} \n{ ','.join(ignored) }")

        if (testing):
            sendLogPost("Testrun complete", "Script exited")
            exit()
        with open(timestampfile, 'w') as f:
            f.write(str(newHighestTimestamp))
        time.sleep(60)

    sendLogPost("Comment monitor down", "No longer authorized")
except Exception as e:
    sendLogPost("Comment monitor failed", str(e))
