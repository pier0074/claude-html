// Secrets out of everything claude-html writes: archives, pages, search,
// the index, the caches. Claude Code's own transcript is never touched.
//
// One function, loaded by convert.js and appended to the archiver by
// save-conversation.sh, so both run the very same rules, under osascript and
// node alike. Plain JavaScript only: nothing of either engine is used here.
//
//   var r = claudeHtmlRedactor(ownListText, true);
//   r.text("export GITHUB_TOKEN=…")    → "export GITHUB_TOKEN=***"
//   r.value(toolInput)                 → the same object, its strings redacted
//   r.counts                           → { assignment: 1 }, rule names only
//   r.find(text)                       → [{ rule, value }]: what text() would
//                                        mask, for the guard, which blocks
//                                        rather than masks
//
// only, when given, is the rules to use, by name: the guard uses the ones
// it is sure of. "safe:" lines in the owner's list are values the owner
// said are not secrets, kept as a salted SHA-256: a rule that matches one
// lets it be. A plain line or a /regex/ of the list still masks what it
// matches, safe or not: an entry the owner wrote wins.
//
// Only formats that say what they are: a known token prefix, a key block,
// a header, a password in a URL, a value whose name says it is secret. No
// guessing from how random a string looks, so hashes, ids and pictures are
// never touched, and a secret of no known shape is missed unless the
// owner's own list names it. What goes in its place is always "***", and a
// second pass changes nothing.
//
// osascript runs regular expressions without a compiler, at about 30 ns a
// character for even the simplest, where indexOf takes a fraction of one.
// So no expression ever scans a whole text: indexOf finds the few places a
// secret could start — a known prefix, a name like "token" — and each rule
// is tried only there, as a sticky expression. node compiles expressions,
// and there one expression finding every such place at once is the faster
// way: compiled says so. The places are the same either way, because no
// text it looks for begins another, and tests/redact.test.js checks it.
function claudeHtmlRedactor(ownText, on, compiled, only) {
  "use strict";
  var MASK = "***";
  // Bumped whenever a rule changes what it matches. The signature that
  // decides whether a page, a cache or an archive is current also holds an
  // md5 of this file, so an edit is never missed even if this is not bumped.
  var VERSION = 1;

  // "token" → "[Tt][Oo][Kk][Ee][Nn]": names are any case, tokens are not.
  function ci(w) {
    return w.replace(/[A-Za-z]/g, function (c) { return "[" + c.toUpperCase() + c.toLowerCase() + "]"; });
  }
  function sticky(src) { return new RegExp(src, "y"); }

  // ── what a value must look like ──
  // Words that stand for a value rather than being one.
  var STANDIN = {};
  ("null nil none undefined true false yes no on off empty string str number int bool boolean " +
   "required optional hidden redacted masked secret secrets password passwords passwd token tokens " +
   "key apikey api_key changeme change_me example sample dummy placeholder value default test " +
   "unknown invalid missing expired notset not_set todo tbd fixme object array any " +
   // How a secret is given, not the secret: --auth basic, "auth": "oauth2".
   "basic bearer digest oauth oauth2 ntlm kerberos sso saml ldap jwt session cookie header bot " +
   "stdin stdout file env prompt interactive ask keychain keyring " +
   // fetch()'s credentials option: credentials: 'include'.
   "include omit same-origin").split(" ")
    .forEach(function (w) { STANDIN[w] = true; });

  function standIn(v) {
    if (v.indexOf(MASK) > -1) return true;                       // done already
    if (/^\$[A-Za-z_{(]|^%[A-Za-z_]+%$/.test(v)) return true;     // $VAR ${VAR} $(cmd) %VAR%
    if (/^<[^>]*>$|^\{\{|^\{[^}]*\}$|^\[[^\]]*\]$/.test(v)) return true;  // <token> {{x}} {x} [x]
    if (/^(process\.env|os\.environ|os\.getenv|import\.meta\.env|env\.|ENV\[|System\.getenv)/i.test(v)) return true;
    if (/^(.)\1*$/.test(v)) return true;                          // xxxxxxxx, ********, ........
    if (/^(x{3,}|\.{3,}|\u2026|\u2022)/i.test(v)) return true;
    if (/^(your|my|some|example|sample|dummy|fake|placeholder|insert|enter|replace|put)([-_ ]|$)/i.test(v)) return true;
    if (/[-_ ](here|goes[-_ ]here)$/i.test(v)) return true;
    if (STANDIN[v.toLowerCase()]) return true;
    // A field's name, not its value: 'newPassword', 'accessToken',
    // 'client_secret' — letters only, ending in a word that says secret.
    if (/^[A-Za-z_-]+$/.test(v)) {
      var w = words(v);
      if (w.length && FIELD_END[w[w.length - 1]]) return true;
    }
    return false;
  }
  // Code that computes a value: token = getToken(), password = cfg.db.pass.
  function codeLike(v) {
    return /[()]/.test(v) || /^[A-Za-z_$][\w$]*(\.[A-Za-z_$][\w$]*)+$/.test(v);
  }
  function pathLike(v) {
    return /^(\/|~\/|\.\.?\/|[A-Za-z]:\\|[A-Za-z][A-Za-z0-9+.-]*:\/\/)/.test(v);
  }
  // A secret is not a word: it has a digit or a symbol in it. Prose such as
  // "password: wrong" and code such as "token: string" never do.
  function secretish(v) {
    return v.length >= 6 && !/^\d+$/.test(v) && /[0-9!@#%^&*+\/=~?]/.test(v);
  }
  // Where an archive or a page cut a long text short. What is left of a
  // value right before it is redacted whatever it looks like.
  var CUT = "\n\u2026[truncated";
  function cutAt(s, end) { return s.substr(end, CUT.length) === CUT; }

  // What a bare value is, when it is code rather than a secret. Each of
  // these was masked in a real conversation about a PHP and Vue codebase.
  // The name of an encoding or an algorithm: secret = Base64 of the key.
  var ENCODING = /^(base(16|32|58|64)(url)?|hex|sha(1|224|256|384|512)?|md5|utf-?8(mb[34])?|utf-?16|latin1|ascii|bcrypt|scrypt|argon2(id|i|d)?|pbkdf2|hmac|aes(128|192|256)?|rsa(2048|4096)?|ed25519)$/i;
  // A type: ?string, Uint8Array.
  var TYPE = /^\?[A-Za-z_]\w*$|^(Big)?U?[Ii]nt(8|16|32|64)(Clamped)?Array$|^Float(32|64)Array$|^ArrayBuffer$/;
  // A lower-case identifier: utf8mb3_general_ci, acme_demo_sub1_key,
  // user_id2. Words joined by _, two of them with letters, one a word.
  function identifier(v) {
    if (!/^[a-z0-9]+(_[a-z0-9]+)+$/.test(v) || !/[a-z]{3}/.test(v)) return false;
    return v.split("_").filter(function (w) { return /[a-z].*[a-z]/.test(w); }).length >= 2;
  }
  // bin2hex( random_bytes(16) ): a call, with the ( right after its name.
  // Not "V (à changer)", where a space comes first.
  function callAt(v, s, end) {
    return v.indexOf("::") > -1 || v.indexOf("->") > -1 || /^(\(|\s*(::|->))/.test(s.slice(end, end + 16));
  }
  function bareCode(v, s, end) {
    if (/=$/.test(v)) return true;                    // name="password" :errors="…": the next attribute
    if (v.indexOf("::") > -1 || v.indexOf("->") > -1) return true;   // self::base64Url, $this->key
    if (callAt(v, s, end)) return true;
    return ENCODING.test(v) || TYPE.test(v) || identifier(v);
  }

  // The value of a name=value, quoted or bare, judged; keep is the name
  // and what joins it to the value, which stay.
  //
  // How sure the form is decides how much the value must look like one.
  // Strong — a name in capitals, a quoted value, a --flag — any value
  // that is not a stand-in is a secret: DB_PASSWORD=hunter, "token":
  // "123456". Weak — a bare value after a name in running text or code —
  // must have a digit or a symbol, and must not read as code: password:
  // wrong, token: string, secret = Base64(…).
  function valueFix(keep, q, v, s, end, strong) {
    if (v == null || v === "" || standIn(v)) return null;
    if (!cutAt(s, end + q.length)) {
      if (pathLike(v)) return null;
      if (q && (v.match(/ /g) || []).length > 2) return null;     // a sentence, not a secret
      // A quoted value with a space and nothing but letters is a label:
      // "password": "Mot de passe".
      if (q && / /.test(v) && !secretish(v)) return null;
      if (!q && (v.charAt(0) === "-" || codeLike(v) || /=$/.test(v) || callAt(v, s, end))) return null;
      if (!strong && (!secretish(v) || codeLike(v) || (!q && bareCode(v, s, end)))) return null;
    }
    return keep + q + MASK + q;
  }
  // The four ways a value is written, as the last four groups of a match.
  // A quoted value is the strong form; so is every value when strong says.
  function quoted(m, at, keep, s, strong) {
    var q = m[at] != null ? '\\"' : m[at + 1] != null ? '"' : m[at + 2] != null ? "'" : "";
    var v = m[at] != null ? m[at] : m[at + 1] != null ? m[at + 1] : m[at + 2] != null ? m[at + 2] : m[at + 3];
    return valueFix(keep, q, v, s, m.index + m[0].length - q.length, !!strong || q !== "");
  }

  // ── the rules ──
  // Each is { name, re, fix }: re is sticky, tried only where the anchors
  // below put it; fix(m, s) gives the replacement for the whole match, or
  // null for "not a secret after all". Without a fix the whole match goes.
  // Their order settles which wins where two could start at one place.
  var KW = "(?:" + [ci("password"), ci("passwd"), ci("passphrase"), ci("pwd"), ci("secret"), ci("token"),
    ci("api") + "[_-]?" + ci("key"), ci("access") + "[_-]?" + ci("key"), ci("private") + "[_-]?" + ci("key"),
    ci("client") + "[_-]?" + ci("secret"), ci("auth"), ci("credentials?"), ci("motdepasse"), ci("mdp")].join("|") + ")";
  // "pass" only as a word of the name of its own: db_pass, PASS, not bypass.
  var KW_PASS = "(?:[A-Za-z0-9_.-]*?[_.-])?" + ci("pass");
  var KW_TAIL = "(?:[_.-]?(?:" + [ci("key"), ci("token"), ci("secret"), ci("value"), ci("string"), ci("hash")].join("|") + "))?";
  // A value: in quotes (with JSON's backslash before them, in text that is
  // itself JSON), or bare up to where code or a URL would end it.
  var VALUE = '(?:\\\\"((?:[^"\\\\\\n]|\\\\[^"])*)\\\\"|"((?:[^"\\\\\\n]|\\\\.)*)"|\'([^\'\\n]*)\'|' +
              "([^\\s\"'`<>(){}\\[\\],;&|\\\\]+))";
  var TOKEN_START = "(?:sk-|gh[pousr]_|github_pat_|glpat-|AKIA|ASIA|AIza|xox[abposr]-|xapp-|[sr]k_(?:live|test)_|" +
                    "whsec_|npm_|pypi-|hf_|SG\\.|eyJ)";
  function keepHead(m) { return m[1] + MASK; }
  // A name=value judged as the weak form, quoted or not.
  function weak(m, s) {
    var at = 2, q = m[at] != null ? '\\"' : m[at + 1] != null ? '"' : m[at + 2] != null ? "'" : "";
    var v = m[at] != null ? m[at] : m[at + 1] != null ? m[at + 1] : m[at + 2] != null ? m[at + 2] : m[at + 3];
    return valueFix(m[1], q, v, s, m.index + m[0].length - q.length, false);
  }
  // A password given to a command after its flag, quoted or not.
  function flagged(m) {
    var v = m[2], q = /^['"]/.test(v) ? v.charAt(0) : "";
    if (q) v = v.slice(1, -1);
    return !v || standIn(v) ? null : m[1] + q + MASK + q;
  }
  // The words of a name, in lower case: apiKey, API_KEY and api-key are
  // all "api key".
  function words(name) {
    return String(name).replace(/([a-z0-9])([A-Z])/g, "$1 $2").toLowerCase().split(/[^a-z0-9]+/)
      .filter(function (w) { return w; });
  }
  var SECRET_WORD = {}, SECRET_PAIR = {}, AFTER = {}, NOT_SECRET_END = {}, FIELD_END = {};
  "password passwd passphrase secret token key credential credentials auth".split(" ")
    .forEach(function (w) { FIELD_END[w] = true; });
  "password passwd passphrase pwd pass mdp motdepasse secret token auth credential credentials apikey accesskey privatekey clientsecret"
    .split(" ").forEach(function (w) { SECRET_WORD[w] = true; });
  "api key|access key|private key|client secret|mot de|de passe".split("|").forEach(function (w) { SECRET_PAIR[w] = true; });
  ("url uri endpoint host port file path dir name id type method mode count limit length size ttl expiry expires " +
   "policy enabled required max min bytes chars len days hours minutes seconds ms cost rounds algo algorithm " +
   "field column header param prefix suffix regex pattern format timeout retries attempts version hash")
    .split(" ").forEach(function (w) { NOT_SECRET_END[w] = true; });
  // An environment-style name, NAME_IN_CAPITALS, with a word that says
  // secret anywhere in it and no word at its end that says otherwise.
  // PASSWORD_HASH holds a hash, which is masked when it looks like one.
  function envName(name, v) {
    if (!/^[A-Z][A-Z0-9_]*$/.test(name)) return false;
    var w = name.toLowerCase().split("_").filter(function (x) { return x; });
    if (!w.length) return false;
    if (w[w.length - 1] === "hash") {
      if (!/^\$(2[aby]?|argon2(id|i|d)?|[1-6])\$|^[0-9a-f]{32,}$|^[A-Za-z0-9+\/]{40,}={0,2}$/.test(String(v || ""))) return false;
    } else if (NOT_SECRET_END[w[w.length - 1]]) return false;
    for (var i = 0; i < w.length; i++) {
      if (SECRET_WORD[w[i]] || (i + 1 < w.length && SECRET_PAIR[w[i] + " " + w[i + 1]])) return true;
    }
    return false;
  }
  // The key of a value in a tool's input, a header, a JSON object: its
  // last word says secret (token, password, apiKey, x-api-key,
  // Authorization, Cookie), or its last but one does before key, value or
  // string (secret_key, password_value).
  "authorization cookie".split(" ").forEach(function (w) { SECRET_WORD[w] = true; });
  var KEY_TAIL = { key: true, value: true, string: true };
  function secretKey(name) {
    var w = words(name), n = w.length;
    function at(e) {
      return e >= 0 && (SECRET_WORD[w[e]] || (e > 0 && SECRET_PAIR[w[e - 1] + " " + w[e]]));
    }
    return n > 0 && (at(n - 1) || (KEY_TAIL[w[n - 1]] && at(n - 2)));
  }

  var RULES = [
    // A whole key block, or what is left of one that was cut off.
    { name: "private-key", re: sticky("-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY(?: BLOCK)?-----(?:[\\s\\S]*?" +
      "-----END (?:[A-Z0-9]+ )*PRIVATE KEY(?: BLOCK)?-----|(?:[A-Za-z0-9+/=\\r]|\\n(?!\\u2026)|\\\\[nr]|" +
      "Proc-Type:[^\\n]*|DEK-Info:[^\\n]*)*)") },
    { name: "jwt", re: sticky("\\beyJ[A-Za-z0-9_-]{5,}\\.eyJ[A-Za-z0-9_-]{5,}\\.[A-Za-z0-9_-]*") },
    { name: "anthropic", re: sticky("\\bsk-ant-[A-Za-z0-9_-]{20,}") },
    { name: "openai", re: sticky("\\bsk-(?:proj-|svcacct-|admin-)?(?=[A-Za-z0-9_-]*\\d)[A-Za-z0-9_-]{20,}") },
    { name: "github", re: sticky("\\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})") },
    { name: "gitlab", re: sticky("\\bglpat-[A-Za-z0-9_-]{20,}") },
    { name: "aws-key-id", re: sticky("\\b(?:AKIA|ASIA|ABIA|ACCA)[A-Z0-9]{16}\\b") },
    { name: "google-api-key", re: sticky("\\bAIza[A-Za-z0-9_-]{35}(?![A-Za-z0-9_-])") },
    { name: "slack-token", re: sticky("\\b(?:xox[abposr]-[A-Za-z0-9-]{10,}|xapp-\\d-[A-Za-z0-9-]{10,})") },
    // A webhook's address is its secret; the host and path stay readable.
    { name: "slack-webhook", re: sticky("(hooks\\.slack\\.com/(?:services|workflows|triggers)/)[A-Za-z0-9/_-]{8,}"),
      fix: keepHead },
    { name: "discord-webhook", re: sticky("(discord(?:app)?\\.com/api/webhooks/\\d+/)[A-Za-z0-9_-]{20,}"),
      fix: keepHead },
    { name: "stripe", re: sticky("\\b(?:[sr]k_(?:live|test)_[A-Za-z0-9]{16,}|whsec_[A-Za-z0-9]{20,})") },
    { name: "npm", re: sticky("\\bnpm_[A-Za-z0-9]{36}(?![A-Za-z0-9])") },
    { name: "pypi", re: sticky("\\bpypi-AgEIcHlwaS5vcmc[A-Za-z0-9_-]{50,}") },
    { name: "huggingface", re: sticky("\\bhf_[A-Za-z0-9]{34,}") },
    { name: "sendgrid", re: sticky("\\bSG\\.[A-Za-z0-9_-]{22}\\.[A-Za-z0-9_-]{43}(?![A-Za-z0-9_-])") },
    { name: "twilio", re: sticky("\\bSK[0-9a-fA-F]{32}\\b") },
    { name: "telegram", re: sticky("\\b\\d{8,10}:AA[A-Za-z0-9_-]{33}(?![A-Za-z0-9_-])") },
    // A bot token has no prefix of its own, so it is looked for only in a
    // text that says "discord", and its first part must hold a digit.
    { name: "discord-token", re: sticky("\\b[MNO](?=[A-Za-z0-9_-]{0,26}\\d)[A-Za-z0-9_-]{23,27}\\." +
      "[A-Za-z0-9_-]{6}\\.[A-Za-z0-9_-]{27,40}(?![A-Za-z0-9_-])") },
    // Authorization: Bearer …, Basic …, token …: the scheme stays.
    { name: "auth-header", re: sticky("(" + ci("authorization") + "[\"']?\\s*[:=]\\s*[\"']?(?:(?:" +
      [ci("bearer"), ci("basic"), ci("token"), ci("bot"), ci("digest"), ci("negotiate")].join("|") +
      ")\\s+)?)([A-Za-z0-9._~+/=:-]+)"),
      fix: function (m, s) {
        if (!cutAt(s, m.index + m[0].length) && (m[2].length < 8 || standIn(m[2]))) return null;
        return m[1] + MASK;
      } },
    { name: "bearer", re: sticky("(\\b[Bb]earer\\s+)([A-Za-z0-9._~+/-]{20,}=*)"),
      fix: function (m) { return /\d/.test(m[2]) && !standIn(m[2]) ? m[1] + MASK : null; } },
    // scheme://user:password@host — the user and the host stay.
    { name: "url-password", re: sticky("([A-Za-z][A-Za-z0-9+.-]{1,20}://[^\\s/?#@:'\"<>]*:)([^\\s/?#@'\"<>]+)@"),
      fix: function (m) { return standIn(m[2]) ? null : m[1] + MASK + "@"; } },
    // curl -u user:password, --user user:password.
    { name: "user-password", re: sticky("((?:-u|--user)(?:\\s+|=)[\"']?[^\\s:'\"]+:)([^\\s'\"]+)"),
      fix: function (m, s) {
        var v = m[2];
        if (standIn(v)) return null;
        // After curl or wget any value is the password; elsewhere -u a:b is
        // as often docker's uid:gid, which has no letters.
        var line = s.slice(s.lastIndexOf("\n", m.index) + 1, m.index);
        if (/(^|[\s\/])(curl|wget|http)(\s|$)/.test(line)) return m[1] + MASK;
        if (!cutAt(s, m.index + m[0].length) && (!secretish(v) || codeLike(v))) return null;
        return m[1] + MASK;
      } },
    // --password value, --api-key=value. Not --password-stdin.
    { name: "flag", re: sticky("(--(?:[A-Za-z0-9]+-)*(?:" + KW + "|" + ci("pass") + ")(?:-(?:" + ci("key") + "|" + ci("token") + "|" +
      ci("secret") + "))?(?:=|\\s+))" + VALUE),
      fix: function (m, s) { return quoted(m, 2, m[1], s, true); } },
    { name: "aws-secret", re: sticky("((?:" + ci("aws") + "_?)?" + ci("secret") + "_?" + ci("access") + "_?" +
      ci("key") + "[\"']?\\s*[:=]\\s*[\"']?)([A-Za-z0-9/+=]{40})(?![A-Za-z0-9/+=])"),
      fix: keepHead },
    // NAME=value, NAME: value, "name": "value", export NAME=value,
    // Password=value; — the name stays, the value goes.
    { name: "assignment", re: sticky("((?:[A-Za-z0-9_.-]*?" + KW + "|" + KW_PASS + ")" + KW_TAIL +
      "(?:\\\\?[\"'])?\\s*(?::=|=>|[:=])\\s*(?:\\[\\s*)?)" + VALUE),
      fix: function (m, s) {
        // :secret-key="x1", @token="…": a Vue binding, whose value is code.
        if (/[:@]/.test(s.charAt(m.index - 1)) && /=/.test(m[1])) return weak(m, s);
        return quoted(m, 2, m[1], s);
      } },
    // Cookie: session=…; the whole value, when it holds a digit or a
    // symbol beside its = signs, as a session id does.
    { name: "cookie", re: sticky("(" + ci("cookie") + "[\"']?\\s*[:=]\\s*[\"']?)([^\"'\\n]+)"),
      fix: function (m) {
        var v = m[2].replace(/\s+$/, "");
        if (standIn(v) || !/[0-9!@#%^&*+\/~?]/.test(v.replace(/=/g, ""))) return null;
        return m[1] + MASK + m[2].slice(v.length);
      } },
    // An environment variable's name says so with a word anywhere in it:
    // SECRET_KEY_BASE, GITHUB_TOKEN_PROD, TOKEN_GITHUB. Only in capitals,
    // where a name is a variable, and not when it ends in a word that
    // makes it something else: AUTH_URL, TOKEN_LIMIT, SECRET_NAME.
    { name: "env-name", re: sticky("([A-Z][A-Z0-9_]*)(\\s*[:=]\\s*)" + VALUE),
      fix: function (m, s) {
        var v = m[3] != null ? m[3] : m[4] != null ? m[4] : m[5] != null ? m[5] : m[6];
        if (!envName(m[1], v)) return null;
        // NAME= word, in a shell, is an empty variable for the command
        // after it: TEST_DB_PASSWORD= echo x. A bare value after "= " is
        // judged as the weak form; a quoted one, or YAML's "NAME: value",
        // stays strong.
        var spaced = /=\s+$/.test(m[2]) && m[6] != null;
        return quoted(m, 3, m[1] + m[2], s, !spaced);
      } },
    // mot de passe : …, as the owner writes it.
    { name: "mot-de-passe", re: sticky("(" + ci("mot") + " " + ci("de") + " " + ci("passe") + "\\s*[:=]\\s*)" + VALUE),
      fix: function (m, s) { return quoted(m, 2, m[1], s); } },
    // mysql -pV, and the like: the password joined to the flag.
    { name: "mysql-password", re: sticky("(-p)('[^'\\n]*'|\"[^\"\\n]*\"|[^\\s'\"]+)"),
      fix: function (m) { return flagged(m); } },
    // sshpass -p V.
    { name: "sshpass", re: sticky("(-p\\s*)('[^'\\n]*'|\"[^\"\\n]*\"|[^\\s'\"]+)"),
      fix: function (m) { return flagged(m); } },
    // What a cut left of a token, now too short for its own rule.
    { name: "cut-token", re: sticky(TOKEN_START + "[A-Za-z0-9_.+/=-]*(?=\\n\\u2026\\[truncated)") }
  ];
  var R = {};
  RULES.forEach(function (r, i) { R[r.name] = i; });

  // ── where each could start ──
  function wordAt(s, i) {          // [A-Za-z0-9_]
    var c = s.charCodeAt(i);
    return (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c === 95;
  }
  function nameAt(s, i) { var c = s.charCodeAt(i); return wordAt(s, i) || c === 45 || c === 46; }
  function spaceAt(s, i) { var c = s.charCodeAt(i); return c === 32 || c === 9 || c === 10 || c === 13; }
  function backOver(s, p, ok, max) {
    var i = p, lim = Math.max(0, p - max);
    while (i > lim && ok(s, i - 1)) i--;
    return i;
  }
  // "key" is a name only as api key, access key, private key: a few
  // characters compared, since it is everywhere in code.
  function keyName(s, p) {
    var b = lowered(s.slice(Math.max(0, p - 8), p)), c = b.slice(-1);
    if (c === "_" || c === "-") b = b.slice(0, -1);
    return b.slice(-3) === "api" || b.slice(-6) === "access" || b.slice(-7) === "private";
  }
  var CUT_START = new RegExp("(?:^|[^A-Za-z0-9_])" + TOKEN_START);

  // [text to find, in any case?, what to do at each place]
  function at(rule) { return function (s, p, push) { push(p, R[rule]); }; }
  var ANCHORS = [
    ["-----BEGIN ", false, at("private-key")],
    ["eyJ", false, at("jwt")],
    ["sk-", false, function (s, p, push) { push(p, R.anthropic); push(p, R.openai); }],
    // Fewer texts to find is less reading: one for the five GitHub kinds,
    // one for three of the AWS ones, each checked where it is found.
    ["gh", false, function (s, p, push) {
      if (s.charAt(p + 3) === "_" && "pousr".indexOf(s.charAt(p + 2)) > -1) push(p, R.github);
    }],
    ["github_pat_", false, at("github")],
    ["glpat-", false, at("gitlab")],
    ["IA", false, function (s, p, push) {
      var k = s.substr(p - 2, 2);
      if (k === "AK" || k === "AS" || k === "AB") push(p - 2, R["aws-key-id"]);
    }],
    ["ACCA", false, at("aws-key-id")],
    ["AIza", false, at("google-api-key")],
    ["xox", false, at("slack-token")], ["xapp-", false, at("slack-token")],
    ["hooks.slack.com/", false, at("slack-webhook")],
    ["_live_", false, function (s, p, push) { push(p - 2, R.stripe); }],
    ["_test_", false, function (s, p, push) { push(p - 2, R.stripe); }],
    ["whsec_", false, at("stripe")],
    ["npm_", false, at("npm")], ["pypi-", false, at("pypi")], ["hf_", false, at("huggingface")],
    ["SG.", false, at("sendgrid")],
    // "SK" starts a thousand words, so a Twilio key is looked for only in a
    // text that says "twilio", as a Discord token in one that says "discord".
    ["twilio", true, function (s, p, push) {
      if (push.twilio) return;
      push.twilio = true;
      var re = /SK[0-9a-fA-F]{32}/g, m;
      while ((m = re.exec(s)) !== null) push(m.index, R.twilio);
    }],
    [":AA", false, function (s, p, push) {
      push(backOver(s, p, function (t, i) { var c = t.charCodeAt(i); return c >= 48 && c <= 57; }, 10), R.telegram);
    }],
    ["discord", true, function (s, p, push) {
      if (s.substr(p, 7) === "discord") push(p, R["discord-webhook"]);
      if (!push.discord) {
        // Once per text: the bot token's own shape, anywhere in it.
        push.discord = true;
        var re = /[MNO][A-Za-z0-9_-]{23,27}\.[A-Za-z0-9_-]{6}\./g, m;
        while ((m = re.exec(s)) !== null) push(m.index, R["discord-token"]);
      }
    }],
    ["bearer", true, at("bearer")],
    ["://", false, function (s, p, push) {
      var i = backOver(s, p, function (t, j) { return wordAt(t, j) || t.charAt(j) === "+" || t.charAt(j) === "." ||
                                                     t.charAt(j) === "-"; }, 21);
      while (i < p && !/[A-Za-z]/.test(s.charAt(i))) i++;
      if (p - i >= 2) push(i, R["url-password"]);
    }],
    ["-u", false, function (s, p, push) {
      if (s.substr(p - 1, 6) === "--user" && (p === 1 || spaceAt(s, p - 2)) &&
          (s.charAt(p + 5) === "=" || /\s/.test(s.charAt(p + 5)))) push(p - 1, R["user-password"]);
      else if ((p === 0 || spaceAt(s, p - 1)) && (s.charAt(p + 2) === "=" || /\s/.test(s.charAt(p + 2)))) {
        push(p, R["user-password"]);
      }
    }],
    // A name that says secret: where it starts decides how it is written.
    ["pass", true, named], ["pwd", true, named], ["secret", true, named], ["token", true, named],
    ["key", true, function (s, p, push) { if (keyName(s, p)) named(s, p, push); }],
    ["auth", true, function (s, p, push) {
      if (lowered(s.substr(p, 13)) === "authorization") push(p, R["auth-header"]);
      named(s, p, push);
    }],
    ["credential", true, named], ["mdp", true, named], ["cookie", true, at("cookie")],
    // mysql -pV: only on a line that runs one of the MySQL tools, so that
    // mkdir -p, ssh -p 2222 and docker run -p 80:80 stay as they are.
    ["-p", false, function (s, p, push) {
      if (!(p === 0 || spaceAt(s, p - 1))) return;
      var next = s.charAt(p + 2);
      if (!next || /\s/.test(next)) return;
      // find's -path, -prune, -print, -perm are words, not -p and a value.
      if (/^-p(ath|rune|rint|erm)(\s|$)/.test(s.substr(p, 7))) return;
      // The MySQL tool must be in the same simple command: not before a
      // |, ;, && or || — mysqldump db | gzip -p4 is gzip's.
      var line = s.slice(s.lastIndexOf("\n", p) + 1, p);
      var cmd = line.split(/\|\||&&|[|;&]/).pop();
      if (/(^|[\s\/])(mysql|mariadb|mysqldump|mysqladmin|mysqlimport)(\s|$)/.test(cmd)) push(p, R["mysql-password"]);
    }],
    // sshpass -p V: the -p after it on its line.
    ["sshpass", false, function (s, p, push) {
      var end = s.indexOf("\n", p), rest = s.slice(p, end < 0 ? s.length : end);
      var m = /\s-p(?=\s*\S)/.exec(rest);
      if (m) push(p + m.index + 1, R.sshpass);
    }],
    [CUT, false, function (s, p, push) {
      var i = backOver(s, p, function (t, j) { return nameAt(t, j) || /[+\/=]/.test(t.charAt(j)); }, 400);
      var m = CUT_START.exec(s.slice(i, p));
      if (m) push(i + m.index + (m[0].length > 0 && !/[A-Za-z]/.test(m[0].charAt(0)) ? 1 : 0), R["cut-token"]);
    }]
  ];
  // Whether something can follow a name at all is a few characters to
  // look at, and most of the places "pass" or "token" turn up are prose:
  // the expressions are tried only where it can.
  function named(s, p, push) {
    var i = backOver(s, p, nameAt, 80);
    if (i > 0 && nameAt(s, i - 1)) return;               // a name too long to be one
    var j = p, end = Math.min(s.length, p + 80);
    while (j < end && nameAt(s, j)) j++;
    var c = s.charAt(j);
    if (s.substr(i, 2) === "--" && (i === 0 || spaceAt(s, i - 1)) && (c === "=" || /\s/.test(c))) push(i, R.flag);
    var k = j;
    if (s.charAt(k) === "\\") k++;
    if (s.charAt(k) === '"' || s.charAt(k) === "'") k++;
    while (k < s.length && /\s/.test(s.charAt(k))) k++;
    c = s.charAt(k);
    if (c !== ":" && c !== "=") return;
    if (i >= 7 && lowered(s.slice(i - 7, i)) === "mot de ") push(i - 7, R["mot-de-passe"]);
    while (i < p && !wordAt(s, i)) i++;
    var name = lowered(s.slice(i, j));
    if (name.indexOf("secret") > -1 && name.indexOf("access") > -1) push(i, R["aws-secret"]);
    push(i, R.assignment);
    if (/^[A-Z][A-Z0-9_]*$/.test(s.slice(i, j))) push(i, R["env-name"]);
  }

  // A lower-cased copy the same length as the text, so that a place in one
  // is the same place in the other, and lower-cased as an expression's i
  // flag sees it: toLowerCase lengthens a very few characters (İ becomes i
  // and a dot) and turns one into a plain letter (the Kelvin sign into k),
  // and those are left as they are.
  function lowered(s) {
    var l = s.toLowerCase();
    if (l.length === s.length && s.indexOf("\u212A") < 0) return l;
    var out = "";
    for (var i = 0; i < s.length; i++) {
      var c = s.charAt(i), lc = c.toLowerCase();
      out += lc.length === 1 && (c < "\u0080" || lc >= "\u0080") ? lc : c;
    }
    return out;
  }

  var counts = {};
  function count(name) { counts[name] = (counts[name] || 0) + 1; }

  // The places, found by indexOf, a text at a time, or by one expression
  // that finds them all in any case, a tree of what they start with — the
  // engine tries far fewer alternatives at each character that way. A text
  // that must be found as written is then checked as written.
  function esc(w) { return w.replace(/[.*+?^${}()|[\]\\\/]/g, "\\$&"); }
  function tree(words) {
    var by = {}, firsts = [];
    words.forEach(function (w) {
      var c = w.charAt(0);
      if (!by[c]) { by[c] = []; firsts.push(c); }
      by[c].push(w.slice(1));
    });
    return firsts.map(function (c) {
      var rest = by[c];
      return esc(c) + (rest.length === 1 ? esc(rest[0]) : "(?:" + tree(rest) + ")");
    }).join("|");
  }
  var BY = {};
  ANCHORS.forEach(function (an) { BY[an[0].toLowerCase()] = an; });
  // Both ways find the same places only while no text to find begins
  // another, in any case: one expression gives one match per place.
  Object.keys(BY).forEach(function (a) {
    Object.keys(BY).forEach(function (b) {
      if (a !== b && b.indexOf(a) === 0) throw new Error("redact.js: " + a + " begins " + b);
    });
  });
  var FIND = new RegExp(tree(ANCHORS.map(function (an) { return an[0].toLowerCase(); })), "gi");

  function builtIn(s) {
    var cands = [];
    function push(p, k) { if (p >= 0) cands.push(p * 64 + k); }
    if (compiled) {
      var m;
      FIND.lastIndex = 0;
      while ((m = FIND.exec(s)) !== null) {
        var hit = BY[m[0].toLowerCase()];
        if (hit[1] || m[0] === hit[0]) hit[2](s, m.index, push);
        FIND.lastIndex = m.index + 1;
      }
    } else {
      var l = null;
      for (var a = 0; a < ANCHORS.length; a++) {
        var an = ANCHORS[a], from = an[1] ? l || (l = lowered(s)) : s;
        var p = from.indexOf(an[0]);
        while (p > -1) {
          an[2](s, p, push);
          p = from.indexOf(an[0], p + 1);
        }
      }
    }
    if (!cands.length) return s;
    // By where they start, and at one place in the rules' order.
    cands.sort(function (x, y) { return x - y; });
    var out = "", last = 0, prev = -1;
    for (var c = 0; c < cands.length; c++) {
      if (cands[c] === prev) continue;
      prev = cands[c];
      var start = Math.floor(prev / 64), k = prev % 64;
      if (start < last) continue;
      var rule = RULES[k];
      rule.re.lastIndex = start;
      var m = rule.re.exec(s);
      if (!m || !m[0]) continue;
      if (only && !only[rule.name]) continue;
      var rep = rule.fix ? rule.fix(m, s) : MASK;
      if (rep === null || rep === m[0]) continue;
      if (SAFE.length || found) {
        // What goes: the match less what the replacement keeps around ***.
        var at = rep.indexOf(MASK), tail = rep.length - at - MASK.length;
        var gone = m[0].slice(at, m[0].length - tail);
        if (isSafe(gone)) continue;
        if (found) found.push({ rule: rule.name, value: gone });
      }
      count(rule.name);
      out += s.slice(last, start) + rep;
      last = start + m[0].length;
    }
    return last ? out + s.slice(last) : s;
  }

  // ── the owner's own list ──
  // A line is a string to find as it is; /a regex/flags is a regex. Lines
  // it cannot use are left out and counted by number: what they say is
  // never repeated anywhere.
  var own = [], ignored = [], literals = [];
  // The plain text a regex must start with, if it says so, to find with
  // indexOf before running it: the regex itself would read every character.
  function literalHead(src, flags) {
    if (/[|]/.test(src) || flags.indexOf("i") > -1) return "";
    var m = /^(?:[A-Za-z0-9_ :=@#%&!,;'"<>~\/-]|\\[.\/\-])*/.exec(src)[0];
    var head = m.replace(/\\(.)/g, "$1");
    // A quantifier after it makes its last character optional.
    if (/^[?*{]/.test(src.slice(m.length))) head = head.slice(0, -1);
    return head.length >= 3 ? head : "";
  }
  var SAFE = [];
  String(ownText || "").split("\n").forEach(function (line, i) {
    var t = line.replace(/^\s+|\s+$/g, "");
    if (!t || t.charAt(0) === "#") return;
    if (t.indexOf("safe:") === 0) {
      var sm = /^safe:([0-9a-f]{16}):([0-9a-f]{32})(\s|$)/.exec(t);
      if (sm) SAFE.push({ salt: sm[1], hash: sm[2] }); else ignored.push(i + 1);
      return;
    }
    var m = /^\/(.+)\/([a-z]*)$/.exec(t);
    if (m && /^[dgimsuyv]*$/.test(m[2])) {
      var re = null;
      try {
        if (!/^[imsu]*$/.test(m[2])) throw new Error("flags");
        re = new RegExp(m[1], m[2] + "g");
        // One that matches nothing at all would match everywhere, and one
        // that matches inside the mask would grow it on every pass.
        var once = new RegExp(m[1], m[2]);
        if (once.test("") || once.test(MASK)) re = null;
      } catch (e) { re = null; }
      if (re) own.push({ name: "own line " + (i + 1), re: re, head: literalHead(m[1], m[2]) });
      else ignored.push(i + 1);
      return;
    }
    if (MASK.indexOf(t) > -1) { ignored.push(i + 1); return; }
    literals.push(t);
  });
  // Longest first, so that one entry inside another cannot leave half of it.
  literals.sort(function (a, b) { return b.length - a.length; });

  function ownPass(s) {
    for (var i = 0; i < literals.length; i++) {
      if (s.indexOf(literals[i]) < 0) continue;
      var pieces = s.split(literals[i]);
      for (var n = 1; n < pieces.length; n++) {
        count("own list");
        if (found) found.push({ rule: "own list", value: literals[i] });
      }
      s = pieces.join(MASK);
    }
    for (var j = 0; j < own.length; j++) {
      var o = own[j];
      if (o.head && s.indexOf(o.head) < 0) continue;
      s = s.replace(o.re, function (x) {
        if (!x || x === MASK) return x;
        count(o.name);
        if (found) found.push({ rule: "own list", value: x });
        return MASK;
      });
    }
    return s;
  }

  // The shortest text any built-in rule can match: shorter ones are let
  // through without a look, and most strings in a transcript are short.
  var MIN = literals.length || own.length ? 1 : 8;

  function text(s) {
    if (!on || typeof s !== "string" || s.length < MIN) return s;
    var r = s;
    // Again until nothing changes, so that redacting twice is redacting once.
    for (var pass = 0; pass < 4; pass++) {
      var next = ownPass(builtIn(r));
      if (next === r) break;
      r = next;
    }
    return r;
  }

  // A string whose key says it is secret, as a name before = would: the
  // same guards, so { token: "string" } and { password: "${PW}" } stay.
  // The strong form: any value but a stand-in, a path or a label.
  function keyed(v) {
    if (SAFE.length && isSafe(v)) return text(v);
    if (standIn(v) || pathLike(v) || (v.match(/ /g) || []).length > 2 || (/ /.test(v) && !secretish(v))) return text(v);
    count("key-value");
    if (found) found.push({ rule: "key-value", value: v });
    return MASK;
  }

  // A tool's input, a parsed record: every string in it, at any depth, in
  // place. Keys are names, not content, and stay as they are; but a key
  // that says secret — token, password, apiKey, Authorization — makes its
  // string the secret, as a name before = does. A number, true or null
  // under one is kept; an object or a list under one is walked as any
  // other, its strings judged by their own keys, a list's by the key above.
  function value(v, depth, key) {
    if (!on) return v;
    var d = depth || 0;
    if (typeof v === "string") return key != null && secretKey(key) ? keyed(v) : text(v);
    if (!v || typeof v !== "object" || d > 64) return v;
    if (Array.isArray(v)) {
      for (var i = 0; i < v.length; i++) v[i] = value(v[i], d + 1, key);
    } else {
      for (var k in v) {
        if (Object.prototype.hasOwnProperty.call(v, k)) v[k] = value(v[k], d + 1, k);
      }
    }
    return v;
  }

  // All the replacements so far, every rule together.
  function total() {
    var n = 0;
    for (var k in counts) n += counts[k];
    return n;
  }

  // What text() would mask, as { rule, value }, one pass, nothing changed.
  var found = null;
  function find(s) {
    found = [];
    try {
      if (on && typeof s === "string" && s.length >= MIN) ownPass(builtIn(s));
      return found;
    } finally { found = null; }
  }
  function isSafe(v) {
    for (var i = 0; i < SAFE.length; i++) if (fingerprint(SAFE[i].salt, v) === SAFE[i].hash) return true;
    return false;
  }

  return {
    on: !!on, version: VERSION, rules: RULES.length, names: RULES.map(function (r) { return r.name; }),
    own: literals.length + own.length, ignored: ignored, safe: SAFE.length,
    counts: counts, total: total, text: text, value: value, find: find, fingerprint: fingerprint
  };
}

// A value's fingerprint: SHA-256 of a salt and the value, as UTF-8, the
// first 32 hex digits. Plain JavaScript, so both engines give the same,
// and only ever run on a value a rule has already matched.
function fingerprint(salt, value) {
  "use strict";
  var bytes = [], str = String(salt) + "\u0000" + String(value);
  for (var i = 0; i < str.length; i++) {
    var c = str.charCodeAt(i);
    if (c >= 0xD800 && c <= 0xDBFF && i + 1 < str.length) {
      var d = str.charCodeAt(i + 1);
      if ((d & 0xFC00) === 0xDC00) { c = 0x10000 + ((c - 0xD800) << 10) + (d - 0xDC00); i++; }
    }
    if (c < 0x80) bytes.push(c);
    else if (c < 0x800) bytes.push(0xC0 | (c >> 6), 0x80 | (c & 63));
    else if (c < 0x10000) bytes.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    else bytes.push(0xF0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
  }
  var K = [0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2];
  var H = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  var bitLen = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  for (var j = 7; j >= 0; j--) bytes.push(j > 3 ? 0 : (bitLen >>> (j * 8)) & 255);
  var w = new Array(64);
  for (var o = 0; o < bytes.length; o += 64) {
    for (var t = 0; t < 16; t++) {
      w[t] = (bytes[o + 4 * t] << 24) | (bytes[o + 4 * t + 1] << 16) | (bytes[o + 4 * t + 2] << 8) | bytes[o + 4 * t + 3];
    }
    for (t = 16; t < 64; t++) {
      var x = w[t - 15], y = w[t - 2];
      var s0 = ((x >>> 7) | (x << 25)) ^ ((x >>> 18) | (x << 14)) ^ (x >>> 3);
      var s1 = ((y >>> 17) | (y << 15)) ^ ((y >>> 19) | (y << 13)) ^ (y >>> 10);
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) | 0;
    }
    var a = H[0], b = H[1], cc = H[2], dd = H[3], e = H[4], f = H[5], g = H[6], h = H[7];
    for (t = 0; t < 64; t++) {
      var S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7));
      var ch = (e & f) ^ (~e & g);
      var t1 = (h + S1 + ch + K[t] + w[t]) | 0;
      var S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10));
      var maj = (a & b) ^ (a & cc) ^ (b & cc);
      var t2 = (S0 + maj) | 0;
      h = g; g = f; f = e; e = (dd + t1) | 0; dd = cc; cc = b; b = a; a = (t1 + t2) | 0;
    }
    H[0] = (H[0] + a) | 0; H[1] = (H[1] + b) | 0; H[2] = (H[2] + cc) | 0; H[3] = (H[3] + dd) | 0;
    H[4] = (H[4] + e) | 0; H[5] = (H[5] + f) | 0; H[6] = (H[6] + g) | 0; H[7] = (H[7] + h) | 0;
  }
  var hex = "";
  for (var k = 0; k < 4; k++) hex += ("0000000" + (H[k] >>> 0).toString(16)).slice(-8);
  return hex;
}
