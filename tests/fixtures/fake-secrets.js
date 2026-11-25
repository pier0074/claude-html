// Fake secrets, one or more per redaction rule, each written the way it
// turns up in a conversation. They are put together from pieces at run
// time, so this file holds nothing a secret scanner would stop a push for,
// and the random parts are made by a fixed sequence, so every run has the
// same ones.
//
//   var F = require("./fixtures/fake-secrets");
//   F.cases     [{ rule, text, secret }]: text holds secret, in context
//   F.probes()  what must never be found again: each secret, and the first
//               ten characters of its random part, so a cut-off half shows
//   F.clean     texts that look a little like secrets and must stay as they are
"use strict";

var seed = 20261119;
function next() { seed = (seed * 1103515245 + 12345) % 2147483648; return seed; }
function pick(chars, n) {
  var s = "";
  for (var i = 0; i < n; i++) s += chars.charAt(Math.floor(next() / 65536) % chars.length);   // the high bits: the low ones repeat
  return s;
}
var ALNUM = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";
var UPPER = "ABCDEFGHJKLMNPQRSTUVWXYZ234567";
var HEX = "0123456789abcdef";
var B64 = ALNUM + "+/";
// Random, and with a digit in it, as real ones nearly always have.
function rnd(n, chars) { return pick(chars || ALNUM, n - 1) + "7"; }

var cases = [];
function add(rule, before, secret, after, core) {
  cases.push({ rule: rule, text: before + secret + (after || ""), secret: secret, core: core || secret });
}
var p = function () { return Array.prototype.join.call(arguments, ""); };

var r;
r = rnd(40); add("anthropic", "use the key ", p("sk-", "ant-", "api03-", r), " for this", r);
r = rnd(40); add("openai", "OPENAI key: ", p("sk-", "proj-", r), "", r);
r = rnd(36); add("github", "my token is ", p("gh", "p_", r), ", keep it", r);
r = rnd(36); add("github", "git remote set-url origin https://", p("gh", "s_", r), "@github.com/o/r", r);
r = rnd(59); add("github", "token ", p("github", "_pat_", r.slice(0, 22), "_", r.slice(22)), " expires soon", r);
r = rnd(20); add("gitlab", "PRIVATE-TOKEN header with ", p("gl", "pat-", r), "", r);
r = rnd(16, UPPER).toUpperCase(); add("aws-key-id", "aws_access_key_id = ", p("AK", "IA", r), "", r);
r = rnd(40, B64); add("aws-secret", "aws_secret_access_key = ", r, "\nregion = eu-west-1", r);
r = rnd(35); add("google-api-key", "maps?key=", p("AI", "za", r), "&q=paris", r);
r = rnd(24); add("slack-token", "SLACK_BOT=", p("xo", "xb-", "2384910283-", r), "", r);
r = rnd(24); add("slack-webhook", p("post to https://", "hooks.slack.com/services/"), p("T0", "ABCDEFG", "/B0", "HIJKLMN", "/", r), "", r);
r = rnd(24); add("stripe", "charge it with '", p("sk", "_live_", r), "'", r);
r = rnd(32); add("stripe", "endpoint secret ", p("wh", "sec_", r), "", r);
r = rnd(36); add("npm", "the npm publish token is ", p("np", "m_", r), "", r);
r = rnd(60); add("pypi", "upload to PyPI with ", p("py", "pi-", "AgEIcHlwaS5vcmc", r), "", r);
r = rnd(34); add("huggingface", "HF token ", p("h", "f_", r), "", r);
r = rnd(43); add("sendgrid", "sendgrid ", p("S", "G.", rnd(22), ".", r), "", r);
r = rnd(32, HEX); add("twilio", "twilio api key ", p("S", "K", r), "", r);
r = rnd(33); add("telegram", "bot ", p("5820349183", ":A", "A", r), " started", r);
r = rnd(68); add("discord-webhook", p("webhook https://", "discord.com/api/webhooks/", "112233445566778899/"), r, "", r);
r = rnd(27); add("discord-token", "the discord bot logs in with ", p("M", rnd(25), ".", rnd(6), ".", r), " now", r);
r = rnd(43); add("jwt", "the session token is ", p("ey", "J", rnd(20), ".ey", "J", rnd(30), ".", r), "", r);
var body = [rnd(64, B64), rnd(64, B64), rnd(40, B64)];
add("private-key", "here is the key:\n", p("-----BEGIN ", "RSA PRIVATE KEY-----\n", body.join("\n"),
    "\n-----END RSA PRIVATE KEY-----"), "\nkeep it safe", body[0]);
var body2 = [rnd(64, B64), rnd(30, B64)];
add("private-key", '{"private_key": "', p("-----BEGIN ", "PRIVATE KEY-----\\n", body2.join("\\n"),
    "\\n-----END PRIVATE KEY-----\\n"), '"}', body2[0]);
r = rnd(32); add("auth-header", 'curl -H "Authorization: Bearer ', r, '" https://api.example.com', r);
r = rnd(24, B64); add("auth-header", "Authorization: Basic ", r, "", r);
r = rnd(14); add("url-password", "DATABASE_URL=postgres://admin:", r, "@db.internal:5432/app", r);
r = rnd(12); add("user-password", "curl -u alice:", r, " https://api.example.com/v1", r);
r = rnd(14); add("flag", "mysql -h db --password=", r, " app", r);
r = rnd(16); add("flag", "deploy --api-key ", r, " --verbose", r);
r = rnd(15); add("assignment", "export DB_PASSWORD=", r, "", r);
r = rnd(18); add("assignment", '{"client_secret": "', r, '", "id": 4}', r);
r = rnd(13); add("assignment", "Server=db;User Id=sa;Password=", r, ";", r);
r = rnd(20); add("assignment", "x-api-key: ", r, "", r);
// Everyday .env and shell forms with no known prefix.
r = rnd(16); add("env-name", "SECRET_KEY_BASE=", r, "", r);
r = rnd(16); add("env-name", "export GITHUB_TOKEN_PROD=", r, "", r);
r = rnd(16); add("env-name", "API_KEY_ANTHROPIC=", r, "", r);
r = rnd(16); add("env-name", "env:\n  TOKEN_GITHUB: ", r, "\n", r);
r = rnd(14); add("assignment", "DB_PASS=", r, "", r);
r = rnd(14); add("assignment", "db_pass: ", r, "", r);
r = rnd(14); add("assignment", "pass: ", r, "", r);
r = rnd(14); add("mot-de-passe", "le mot de passe : ", r, " (à changer)", r);
r = rnd(14); add("mot-de-passe", "mot de passe = ", r, "", r);
r = rnd(14); add("assignment", "mdp: ", r, "", r);
r = rnd(14); add("assignment", "motdepasse=", r, "", r);
r = rnd(14); add("mysql-password", "mysql -u root -p", r, " app_db", r);
r = rnd(14); add("mysql-password", "mysqldump -uroot -p'", r, "' app > dump.sql", r);
r = rnd(14); add("sshpass", "sshpass -p ", r, " ssh deploy@host", r);
r = rnd(14); add("sshpass", "sshpass -p '", r, "' scp a host:b", r);
r = rnd(14); add("flag", "tool --pass ", r, " --verbose", r);
r = rnd(24); add("cookie", "Cookie: theme=dark; sid=", r, "", r);
// Still masked once code is told apart from values (review of a PHP and
// Vue session).
var P = function () { return Array.prototype.join.call(arguments, ""); };
add("assignment", "DB_PASSWORD=", P("Zq7xK2", "mP9wL4"), "", "Zq7xK2mP9w");
add("assignment", "password: ", P("Zq7xK2", "mP9wL5"), "", "Zq7xK2mP9w");
add("assignment", "private const SECRET = '", P("a1b2-c3d4", "-e5f6"), "'", "a1b2-c3d4-");
add("assignment", "'private_key' => '", P("k9#m", "P2x"), "'", "k9#mP2x");
add("assignment", "token: ", P("9f8e7d6c5b", "4a3210ffee"), "", "9f8e7d6c5b");
add("assignment", "secret=", P("AbC123", "xyz_9Q"), "", "AbC123xyz_");
add("mysql-password", "mysql -uroot -p", P("ab", "cd"), " db", P("ab", "cd db"));
add("assignment", "ACME_SUB2_SECRET= ", P("A1B2C3D4", "-E5F6"), "", "A1B2C3D4-E");
r = rnd(64, HEX); add("assignment", '{"csrfToken":"', r, '"}', r);
// The strong forms take any value that is not a stand-in: letters only,
// digits only.
function letters(n) { return pick("bcdfghjkmnpqrstvwxz", n); }
function digits(n) { return pick("123456789", n); }
r = letters(10); add("env-name", "DB_PASSWORD=", r, "", r);
r = letters(10); add("env-name", "export API_TOKEN=", r, "", r);
r = letters(10); add("assignment", 'password: "', r, '"', r);
r = letters(10); add("assignment", "'secret' => '", r, "',", r);
r = digits(9); add("assignment", '{"token":"', r, '"}', r);
r = letters(10); add("flag", "app --password ", r, " --verbose", r);
r = letters(10); add("flag", "app --password=", r, "", r);
r = letters(10); add("url-password", "postgres://app:", r, "@db.internal/app", r);
r = letters(10); add("user-password", "curl -u alice:", r, " https://api.example.com", r);
r = letters(10); add("sshpass", "sshpass -p ", r, " ssh deploy@host", r);
r = letters(10); add("mysql-password", "mysql -uroot -p", r, " app", r);
r = letters(10); add("mysql-password", "docker exec db mysql -uroot -p", r, " app", r);
// Seen in a real PHP and JS session, and right to mask: letters alone.
// ("toor" here, as "root" is also the user's name in these lines.)
add("env-name", "  MYSQL_ROOT_PASSWORD: ", P("to", "or"), "\n");
add("env-name", "  TEST_DB_PASSWORD: ", P("to", "or"), "\n");
add("env-name", "MYSQL_PWD=", P("to", "or"), " mysql app");
add("mysql-password", "mysql -h 127.0.0.1 -uroot -p", P("to", "or"), " app");
add("assignment", "'login' => 'root', 'password' => '", P("to", "or"), "',");
r = letters(10); add("assignment", "'password' => '", r, "'", r);
r = letters(8); add("assignment", '"token":"', r, '"', r);

var clean = [
  "commit 3f2a9c1b7e5d4a6f8b0c2e4d6f8a0b2c4d6e8f0a by someone",
  "session 123e4567-e89b-12d3-a456-426614174000 resumed",
  "sha256 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
  "the password is wrong", "reset your token", "token = getToken()", "password: ${DB_PASSWORD}",
  "API_KEY=$API_KEY", "export TEST_DB_PASSWORD=\"\\$(cat $D/pw)\"", "SECRET_KEY=\\${SECRET_KEY}",
  "DB_PASSWORD=$$(cat .pw) make db", "TOKEN=$${CI_TOKEN}", "echo $TOKEN | docker login --password-stdin", "see https://example.com/docs?page=2",
  "ssh git@github.com and user@host", "mail jane.doe@example.com", "max_tokens=4096",
  "const token = req.headers.authorization;", "password = os.environ['DB_PASSWORD']",
  "Authorization: Bearer $TOKEN", "apiKey: string;", "secret: true", "token: <your token here>",
  "auth: required", "password=********", "db.password=***", "docker run -u 1000:1000 img",
  "the author: Jane Austen", "task-runner and desk-lamp", "PWD=/Users/me/project", "TASK SKIP DISK",
  // Pinned by review: each of these must stay exactly as it is.
  "max_tokens: 128000", "tokens: 12.5k total", "author: bob99", "tokenizer: gpt2-large",
  'git commit --author="A B <a@b.co>"', "https://example.com:8080/path?x=1", "git@github.com:o/r.git",
  "keyboard: us-intl2", "primary key: id2", "cache_key: sessions/2026-11", "token_count=4096",
  "password_hash: bcrypt", "if (password === confirm2) ok()", "const token = req.headers.x1;",
  "secret santa: 2026 edition", "passed: 12 tests", "authority: level2", "sort -u file1 file2",
  "input_tokens: 4.8k", "git push -u origin feature/x-2",
  "token_count: 12k", "password_policy: min8", "bypass=abc123x", "compass: n2e", "pass: true",
  "curl -p 8080 x", "ssh -p 2222 host", "mkdir -p dir1", "docker run -p 80:80 img", "cp -p a1 b2",
  "MAX_TOKENS=4096", "GITHUB_TOKEN_COUNT=5000x", "AUTH_URL=https://x.io/a2", "AUTH_METHOD=oauth2",
  "TOKEN_ENDPOINT=/v2/t", "AWS_KEY_ID=K2X", "SECRET_NAME=prod2", "API_KEY_FILE=/etc/k2",
  "CLIENT_SECRET_PATH=x/y2", "PASSWORD_POLICY=min8", "mysql -u root -p app_db", "Cookie: theme=dark", "ssh -p2222 host", "tar -pczf a2.tgz dir1",
  // Code, not values (review of a PHP and Vue session).
  '<Field label="Secret key" name="secretKey" :errors="errors" />', 'name="accessKey" :errors="formErrors"',
  'name="password" :errors="e2"', 'name="keyPassphrase" :errors="errors"', 'name="token" v-model="form.token"',
  'id="password" type="password"', ':secret-key="x1"',
  "$secret = base64_encode( random_bytes(32) );", "'token' => bin2hex( random_bytes(16) ),",
  "authToken: toBase64( sub.getKey('auth') )", "'authToken' => self::base64Url( $x ),", "secret = Base64(raw)",
  '"secret" = Base64 of the public key', "secret = Base64 public key", "token = $this->makeToken2()",
  "privateKey: ?string", "apiKey: ?string", "token: ?int", "password: string|null", "secret: Buffer | undefined",
  "token?: string", "authToken: Uint8Array", "key: CryptoKey", "hash: sha256",
  "users.password: utf8mb3_general_ci", "SiteCredentials: acme_demo_sub1_key", "token: user_id2", "secret: app_secret_v2",
  // Stand-ins in the strong forms, and form vocabulary, which is not a
  // name and its value.
  '"password": "password"', "PASSWORD=changeme", '"token": "string"', "'secret' => 'secret'",
  "TOKEN=your_token_here", 'PASSWORD=""', 'password: "<password>"', '"type": "string"', '"token": "number"',
  '<input type="password" name="password" id="token">', 'label="Password" placeholder="Password"',
  'autocomplete="current-password"', '"password": "Mot de passe"', "deploy --auth basic", "app --password-file ./pw",
  "mysql db < x.sql; find . -not -path './vendor/*' -print", "mysqldump db | gzip -p12", "mysql db < a.sql && pigz -p8x b",
  // fetch()'s option, limits and settings named after a secret, a shell's
  // empty variable before a command, and a field's name as a value.
  "fetch(url, { method: 'POST', credentials: 'include' })", "credentials: 'same-origin'", "credentials: \"omit\"",
  "withCredentials: true", 'credentials: "include"',
  "PASSWORD_MAX_BYTES = 72", "PASSWORD_MIN_LENGTH=8", "TOKEN_TTL=3600", "SECRET_ROTATION_DAYS=30",
  "PASSWORD_HASH_COST=12", "TOKEN_BYTES=32", "PASSWORD_ALGO=bcrypt", "TOKEN_HEADER='X-Auth'",
  "PASSWORD_FIELD='pwd'", "PASSWORD_REGEX='^[a-z]{8,}$'", "AUTH_TIMEOUT=30", "PASSWORD_HASH=bcrypt",
  "TEST_DB_PASSWORD= echo x", "TEST_DB_PASSWORD= when it runs", "DB_PASSWORD= export Y=1",
  "CREDENTIALS_KEY = 'DatabasePassword'", "'password' => 'newPassword'", "tokenField: 'accessToken'",
  "name: 'apiKey'", "key => 'client_secret'"
];

function probes() {
  var out = [];
  cases.forEach(function (c) { out.push(c.secret); out.push(c.core.slice(0, 10)); });
  return out.filter(function (x, i) { return out.indexOf(x) === i; });
}

module.exports = { cases: cases, clean: clean, probes: probes, rnd: rnd };
