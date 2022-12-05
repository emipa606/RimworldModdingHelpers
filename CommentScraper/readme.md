# Comment Scraper

Script fetches unread notifications of steam-comments

It then loads each mod-page and pushes the comments to a Discord channel via webhook

Called with the current two-factor code as first parameter

If anything is added as a second parameter it will run in test-mode. This will push comments to the defined text-channel instead and not use the user-session when fetching so the notification will not become "read"

If not run in test-mode the script will continue to run once every minute until aborted or the active session times out. If the session expires it will report this to the test-webhook