"""Scrapes steam for comments

Returns:
_type_: _description_
"""
import sys
import os
import subprocess
import json
import re
from pathlib import Path
from time import sleep
import psutil
import steam.webauth as wa
from bs4 import BeautifulSoup
import requests

CONFIG_PATH = "./comment_scraper.json"
if not os.path.isfile(CONFIG_PATH):
    print(f"No config-file found: {CONFIG_PATH}, create and try again")
    sys.exit()

REPLIES = "./replies.json"
COMMENTS = "./comments/"


if not os.path.isfile(REPLIES):
    Path(REPLIES).touch()


def read_json(file_path):
    """Reads json file"""
    with open(file_path, "r", encoding="utf8") as file:
        return json.load(file)


def remove_json(file_path, mod_id):
    """Clears json comment"""
    current_json = read_json(file_path)
    current_json.pop(mod_id)
    with open(file_path, 'w', encoding="utf8") as file:
        file.write(current_json)
        file.close()


def clear_json(file_path):
    """Clears json file"""
    with open(file_path, 'w', encoding="utf8") as file:
        file.write("{}")
        file.close()


mypid = psutil.Process().pid
mycmdline = psutil.Process().cmdline()
for proc in psutil.process_iter(['pid', 'cmdline']):
    if proc.pid != mypid and proc.info['cmdline'] == mycmdline:
        print(f"Found running process, killing pid: {proc.pid}")
        proc.kill()


settings = read_json(CONFIG_PATH)
webhookUrl = settings["discord_channel"]
infoWebhookUrl = settings["discord_test_channel"]
logWebhookUrl = settings["discord_log_channel"]
logWebhookUrl = settings["discord_log_channel"]
displayname = settings["steam_displayname"]
username = settings["steam_username"]
password = settings["steam_password"]
timestampfile = settings["timestamp_filename"]
timestampfilePath = f"./{timestampfile}"

if not os.path.isfile(timestampfilePath):
    with open(timestampfile, 'w', encoding="utf8") as f:
        f.write('')


def sendDiscordPost(data, url):
    result = requests.post(url, json=data)
    try:
        result.raise_for_status()
    except requests.exceptions.HTTPError as err:
        print(err)
    else:
        print(f"Payload delivered successfully, code {result.status_code}.")


def sendlogpost(title, logtext):
    """Sends message to the log-channel"""
    logtext = htmltodiscord(logtext)
    data = {}
    data["embeds"] = [
        {
            "description": logtext,
            "title": title
        }
    ]
    sendDiscordPost(data, logWebhookUrl)


def sendtestpost(title, logtext):
    """Sends message to the test-channel"""
    logtext = htmltodiscord(logtext)
    data = {}
    data["embeds"] = [
        {
            "description": logtext,
            "title": title
        }
    ]
    sendDiscordPost(data, infoWebhookUrl)


def senddiscordpost(modurl, modtitle, authorname, authorpagelink, authorimage, messagetext):
    """Sends message to the real channel"""
    messagetext = htmltodiscord(messagetext)
    messagetext = steamemoticon(messagetext)
    data = {}
    data["embeds"] = [
        {
            "author": {
                "name": authorname,
                "url": authorpagelink,
                "icon_url": authorimage
            },
            "description": messagetext,
            "title": modtitle,
            "url": modurl
        }
    ]
    sendDiscordPost(data, webhookUrl)


def steamemoticon(message):
    """Replaces steam emoticons to emojis"""
    message = message.replace(
        'https://community.akamai.steamstatic.com/economy/', ''
    )
    message = message.replace(
        'https://community.cloudflare.steamstatic.com/economy/', ''
    )
    message = message.replace(
        'emoticon/steamthumbsup', ':thumbsup:')
    message = message.replace(
        'emoticon/steamthumbsdown', ':thumbsdown:')
    message = message.replace(
        'emoticon/bigups', ':thumbsup:')
    message = message.replace(
        'emoticon/steamhappy', ':smiley:')
    message = message.replace(
        'emoticon/steamfacepalm', ':person_facepalming:')
    message = message.replace(
        'emoticon/reheart', ':heartpulse:')
    message = message.replace(
        'emoticon/luv', ':heart:')
    message = message.replace(
        'emoticon/LIS_pixel_heart', ':heart:')
    message = message.replace(
        'emoticon/love', ':heart:')
    message = message.replace(
        'emoticon/steamhearteyes', ':heart_eyes:')
    message = message.replace(
        'emoticon/blocked', ':shield:')
    message = message.replace(
        'emoticon/nekoheart', ':heart:')
    message = message.replace(
        'emoticon/yay', ':smiley:')
    message = message.replace(
        'emoticon/vanilla2', ':eye:')
    message = message.replace(
        'emoticon/awywink', ':wink:')
    message = message.replace(
        'emoticon/auimp', ':space_invader:')
    message = message.replace(
        'emoticon/mhwno', ':no_entry:')
    message = message.replace(
        'emoticon/csgoanarchist', ':cowboy:')
    message = message.replace(
        'emoticon/steamsad', ':pensive:')
    return message


def htmltodiscord(message):
    """Converts html-code to discord-friendly code"""
    linkfilter = r'<a.*(?:href=")(?P<link>[^"]*)[^>]*>(?P<text>[^<]*)<\/a>'
    imagefilter = r'<img.*src="(?P<link>.*)".*>'
    imagefilter = r'<img.*src="(?P<link>.*)".*>'
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
    message = re.sub(linkfilter, r' \g<link> ', message)
    message = re.sub(imagefilter, r' \g<link> ', message)
    message = re.sub(linkfilter, r' \g<link> ', message)
    message = re.sub(imagefilter, r' \g<link> ', message)
    message = re.sub(externallinkfilter, '', message)
    if len(message) > 4000:
        message = message[0:4000]
    return message


user = wa.WebAuth2()


loggedIn = False
try:
    # result = user.login(username, password)
    twoFactor = subprocess.run(
        ['steamguard', '--verbosity', 'error'], capture_output=True, text=True).stdout.strip()
    result = user.login(username=username, password=password,
                        twofactor_code=twoFactor)
    loggedIn = user.session.verify
except Exception as e:
    sendtestpost("Comment monitor", f"Fail: {e}")
    sys.exit()
if not loggedIn:
    exit()

try:
    sendlogpost("Comment monitor", f"Login successful: {result}")

    session_id = user.session.cookies._cookies["steamcommunity.com"]['/']['sessionid'].value
    login_secure = user.session.cookies._cookies["steamcommunity.com"]['/']["steamLoginSecure"].value
    cookies = {"sessionid": session_id, "steamLoginSecure": login_secure}
    sendtestpost("Comment monitor", f"Fail: {e}")
    sys.exit()
if not loggedIn:
    exit()

try:
    sendlogpost("Comment monitor", f"Login successful: {result}")

    session_id = user.session.cookies._cookies["steamcommunity.com"]['/']['sessionid'].value
    login_secure = user.session.cookies._cookies["steamcommunity.com"]['/']["steamLoginSecure"].value
    cookies = {"sessionid": session_id, "steamLoginSecure": login_secure}

    while user.session.verify:
        currentNotifications = user.session.get(f'https://steamcommunity.com/id/{displayname}/commentnotifications/').text
        soup = BeautifulSoup(currentNotifications, 'html.parser')

        LASTHIGHESTTIMESTAMP = 0
        with open(timestampfile, "r", encoding="utf8") as f:
            fileContent = f.read()
            if fileContent:
                LASTHIGHESTTIMESTAMP = int(fileContent)
        NEWHIGHESTTIMESTAMP = LASTHIGHESTTIMESTAMP

        notificationsDiv = soup.find(
            "div", {"class": "commentnotifications_header_commentcount"})

        replies = read_json(REPLIES)
        clear_json(REPLIES)
        for reply in replies:
            modid = reply
            comment = replies[reply]
            answerPage = user.session.get(
                f"https://steamcommunity.com/sharedfiles/filedetails/?id={modid}").text
            pageid = answerPage.split(f"_{modid}_area")[0].split("_")[-1]
            commentUrl = f"https://steamcommunity.com/comment/PublishedFile_Public/post/{pageid}/{modid}"
            data = {'comment': comment, 'sessionid': session_id, 'feature2': -1}
            user.session.post(commentUrl, data=data, cookies=cookies)

        if not notificationsDiv:

        replies = read_json(REPLIES)
        clear_json(REPLIES)
        for reply in replies:
            modid = reply
            comment = replies[reply]
            answerPage = user.session.get(
                f"https://steamcommunity.com/sharedfiles/filedetails/?id={modid}").text
            pageid = answerPage.split(f"_{modid}_area")[0].split("_")[-1]
            commentUrl = f"https://steamcommunity.com/comment/PublishedFile_Public/post/{pageid}/{modid}"
            data = {'comment': comment, 'sessionid': session_id, 'feature2': -1}
            user.session.post(commentUrl, data=data, cookies=cookies)

        if not notificationsDiv:
            print('No new notifications')
            sleep(60)
            sleep(60)
            continue

        if notificationsDiv:
            archiveMode = False
            print(f'Found {notificationsDiv.text} new notifications')

            unreadNotifications = soup.findAll(
                "div", {"class": "commentnotification unread"})[::-1]
        else:
            archiveMode = True
            sendtestpost("Comment monitor",
                         "No new notifications, using the last 5 for testing")
            unreadNotifications = soup.findAll(
                "div", {"class": "commentnotification"})[:5]

        somethingsent = False
        somethingsent = False
        for notification in unreadNotifications:
            link = (notification.find("a")['href']).split('&')[0]
            linkPage = user.session.get(link).text
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
                linkPage = user.session.get(link).text
                linkPage = user.session.get(link).text
                linkSoup = BeautifulSoup(linkPage, 'html.parser')
                allComments = linkSoup.findAll(
                    "div", {"class": "commentthread_comment"})
            mainStamp = int(notification.find(
                "div", {"class": "commentnotification_date"}).find("span")['data-timestamp'])
            NEWHIGHESTTIMESTAMP = mainStamp
            if LASTHIGHESTTIMESTAMP == 0:
                LASTHIGHESTTIMESTAMP = mainStamp - 1

            ignored = []

            if archiveMode:
                allComments = [allComments[-1]]

            for comment in allComments:
                hiddenContent = comment.find(
                    "div", {"class": "comment_hidden_content"})
                if hiddenContent:
                    continue
                commentStamp = comment.find(
                    "span", {"class": "commentthread_comment_timestamp"})['data-timestamp']
                if not archiveMode and LASTHIGHESTTIMESTAMP >= int(commentStamp):
                    ignored.append(commentStamp)
                    continue
                author = comment.find(
                    "a", {"class": "commentthread_author_link"}).text.replace(" (", "|").split("|")[0].strip()
                if author == "Mlie":
                    continue
                    "a", {"class": "commentthread_author_link"}).text.replace(" (", "|").split("|")[0].strip()
                if author == "Mlie":
                    continue
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
                if "needs_content_check" in TEXT:
                    continue

                senddiscordpost(link, modName, author,
                                authorPage, imageUrl, TEXT)
                sleep(5)

        with open(timestampfile, 'w', encoding="utf8") as f:
            f.write(str(NEWHIGHESTTIMESTAMP))
        if somethingsent:
            sendlogpost("New comments", "Check them")
        sleep(60)
        if somethingsent:
            sendlogpost("New comments", "Check them")
        sleep(60)

    sendlogpost("Comment monitor down", "No longer authorized")
except Exception as e:
    sendlogpost("Comment monitor failed", str(e))


sendtestpost("Comment monitor", "Restarting")


sendtestpost("Comment monitor", "Restarting")
