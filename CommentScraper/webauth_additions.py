# Add this to the webauth.py file


API_HEADERS = {
    'origin': 'https://steamcommunity.com',
    'referer': 'https://steamcommunity.com/',
    'accept': 'application/json, text/plain, */*'
}


def sendAPIRequest(data, sApiInterface, sApiMethod, sApiVersion):
    sUrl = "https://api.steampowered.com/{}Service/{}/v{}".format(
        sApiInterface, sApiMethod, sApiVersion)
    if sApiMethod == "GetPasswordRSAPublicKey":
        res = requests.get(sUrl, timeout=10, headers=API_HEADERS, params=data)
    else:
        res = requests.post(sUrl, timeout=10, headers=API_HEADERS, data=data)
    res.raise_for_status()
    return res.json()


# Updated implementation of WebAuth for the new steam login method (old one is gutted on valve's end and cannot be used anymore)
# TODO: Steam guard support
# TODO: Replace WebAuth with this new class when everything is fully implemented (steam guard)
class WebAuth2(object):
    username = None
    password = None
    twofactor_code = None
    steamID = None
    steam_id = None
    clientID = None
    requestID = None
    refreshToken = None
    accessToken = None
    session_id = None
    logged_on = False
    session = None
    userAgent = None

    # Pretend to be chrome on windows, made this act as most like a browser as possible to (hopefully) avoid breakage in the future from valve
    def __init__(self, username='', password='', userAgent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36'):
        self.session = requests.session()
        self.userAgent = userAgent
        self.username = username
        self.password = password
        self.session.headers['User-Agent'] = self.userAgent

    def _getRsaKey(self):
        return sendAPIRequest({'account_name': self.username}, "IAuthentication", 'GetPasswordRSAPublicKey', 1)

    def _encryptPassword(self):
        r = self._getRsaKey()

        mod = intBase(r['response']['publickey_mod'], 16)
        exp = intBase(r['response']['publickey_exp'], 16)

        pubKey = rsa_publickey(mod, exp)
        encrypted = pkcs1v15_encrypt(pubKey, self.password.encode('ascii'))
        b64 = b64encode(encrypted)

        return tuple((b64.decode('ascii'), r['response']['timestamp']))

    def _startSessionWithCredentials(self, sAccountEncryptedPassword, iTimeStamp):
        r = sendAPIRequest(
            {'device_friendly_name': self.userAgent,
                'account_name': self.username,
                'encrypted_password': sAccountEncryptedPassword,
                'encryption_timestamp': iTimeStamp,
                'remember_login': '1',
                'remember_login': '1',
                'platform_type': '2',
                'persistence': '1',
                'website_id': 'Community'
             }, 'IAuthentication', 'BeginAuthSessionViaCredentials', 1)
        # if "allowed_confirmations" in r['response']:
        #     print("Respond to steam guard within 10 seconds")
        #     sleep(10)

        self.clientID = r['response']['client_id']
        self.requestID = r['response']['request_id']
        self.steamID = r['response']['steamid']
        self.steam_id = SteamID(self.steamID)
        sendAPIRequest({'client_id': self.clientID,
                        'steamid': self.steamID,
                        'code_type': '3',
                        'code': self.twofactor_code
                        }, 'IAuthentication', 'UpdateAuthSessionWithSteamGuardCode', 1)

    def _startLoginSession(self):
        encryptedPassword = self._encryptPassword()
        self._startSessionWithCredentials(
            encryptedPassword[0], encryptedPassword[1])

    def _pollLoginStatus(self):
        r = sendAPIRequest({
            'client_id': str(self.clientID),
            'request_id': str(self.requestID)
        }, 'IAuthentication', 'PollAuthSessionStatus', 1)
        self.refreshToken = r['response']['refresh_token']
        self.accessToken = r['response']['access_token']

    def _finalizeLogin(self):
        self.sessionID = generate_session_id()
        self.logged_on = True
        for domain in ['store.steampowered.com', 'help.steampowered.com', 'steamcommunity.com']:
            self.session.cookies.set(
                'sessionid', self.sessionID, domain=domain)
            self.session.cookies.set('steamLoginSecure', str(
                self.steam_id.as_64) + "||" + str(self.accessToken), domain=domain)

    def login(self, username='', password='', twofactor_code=''):
        if self.logged_on:
            return self.session

        if username == '' or password == '':
            if self.username == '' and self.password == '':
                raise ValueError("Username or password is provided empty!")
        else:
            self.username = username
            self.password = password
            self.twofactor_code = twofactor_code

        self._startLoginSession()
        self._pollLoginStatus()
        self._finalizeLogin()

        return self.session
