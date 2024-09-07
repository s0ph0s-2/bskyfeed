Xml = require "xml"
Bsky = require "bsky"
Rss = require "rss"
Jsonfeed = require "jsonfeed"
Date = require "date"
local about = require "about"
local re = require 're'
local sqlite3 = require 'lsqlite3'
local feed = require "feed"
AT_URI = re.compile[[^at://(did:[a-z0-9:]+)/app\.bsky\.feed\.(re)?post/([a-z0-9]+)]]
FEED_PATH = re.compile[[^/([A-z0-9:\.]+)/feed\.(json|xml)$]]
DB_FILE = 'bskyfeedCache.sqlite3'

ServerVersion = string.format(
    "%s/%s; redbean/%s",
    about.NAME,
    about.VERSION,
    about.REDBEAN_VERSION
)
ProgramBrand(ServerVersion)
ProgramCache(60 * 60 * 24 * 365, "private")

local heartbeatCounter = 0

function SetupDb()
    if not unix.access(DB_FILE, unix.F_OK) then
        local db = sqlite3.open(DB_FILE)
        db:busy_timeout(1000)
        db:exec[[PRAGMA journal_mode=WAL]]
        db:exec[[PRAGMA synchronous=NORMAL]]
        db:exec[[CREATE TABLE ProfileCache (
            did TEXT PRIMARY KEY,
            handle TEXT,
            displayName TEXT,
            description TEXT,
            avatar TEXT,
            cachedAt TEXT
        );]]
        db:exec[[CREATE TABLE PostCache (
            uri TEXT PRIMARY KEY,
            postBlob BLOB,
            cachedAt TEXT
        );]]
        db:close()
    end
end

SetupDb()

local function setupSql()
    if not Db then
        Db = sqlite3.open(DB_FILE)
        Db:busy_timeout(1000)
        Db:exec[[PRAGMA journal_mode=WAL;]]
        Db:exec[[PRAGMA synchronous=NORMAL;]]
        GetFromProfileCacheStmt = Db:prepare[[
            SELECT
                did, handle, displayName, description, avatar, strftime('%s', cachedAt) AS cachedAt
            FROM
                ProfileCache
            WHERE
                did = ?;
        ]]
        InsertIntoProfileCacheStmt = Db:prepare[[
            INSERT OR REPLACE INTO ProfileCache (
                did, handle, displayName, description, avatar, cachedAt
            ) VALUES (
                ?,   ?,      ?,           ?,           ?,      datetime('now')
            );
        ]]
        GetFromPostCacheStmt = Db:prepare[[
            SELECT
                postBlob, strftime('%s', cachedAt) AS cachedAt
            FROM
                PostCache
            WHERE
                uri = ?;
        ]]
        InsertIntoPostCacheStmt = Db:prepare[[
            INSERT OR REPLACE INTO PostCache (
                uri, postBlob, cachedAt
            ) VALUES (
                ?,   ?,        datetime('now')
            );
        ]]
   end
end

function GetProfileFromCache(did)
    if not GetFromProfileCacheStmt then
        Log(kLogWarn, 'prepare getFromProfileCache failed: ' .. Db:errmsg())
        return nil
    end
    GetFromProfileCacheStmt:reset()
    GetFromProfileCacheStmt:bind(1, did)
    for profile in GetFromProfileCacheStmt:nrows() do -- luacheck: ignore
        return profile
    end
    return nil
end

function PutProfileIntoCache(profile)
    -- print("PutProfileIntoCache: caching " .. EncodeJson(profile))
    if not InsertIntoProfileCacheStmt then
        Log(kLogWarn, 'prepare InsertIntoProfileCacheStmt failed: ' .. Db:errmsg())
        return nil
    end
    InsertIntoProfileCacheStmt:reset()
    InsertIntoProfileCacheStmt:bind(1, profile.did)
    InsertIntoProfileCacheStmt:bind(2, profile.handle)
    InsertIntoProfileCacheStmt:bind(3, profile.displayName)
    InsertIntoProfileCacheStmt:bind(4, profile.description)
    InsertIntoProfileCacheStmt:bind(5, profile.avatar)
    if InsertIntoProfileCacheStmt:step() == sqlite3.DONE then
        return true
    end
    return false
end

function GetPostFromCache(uri)
    if not GetFromPostCacheStmt then
        Log(kLogWarn, 'prepare getFromPostCache failed: ' .. Db:errmsg())
        return nil
    end
    GetFromPostCacheStmt:reset()
    GetFromPostCacheStmt:bind(1, uri)
    for post in GetFromPostCacheStmt:nrows() do -- luacheck: ignore
        local postTable = DecodeJson(post.postBlob)
        if postTable then
            return postTable, post.cachedAt
        else
            return nil
        end
    end
    return nil
end

function PutPostIntoCache(post)
    -- print("PutPostIntoCache: caching " .. EncodeJson(post))
    if not InsertIntoPostCacheStmt then
        Log(kLogWarn, 'prepare InsertIntoPostCacheStmt failed: ' .. Db:errmsg())
        return nil
    end
    InsertIntoPostCacheStmt:reset()
    InsertIntoPostCacheStmt:bind(1, post.uri)
    InsertIntoPostCacheStmt:bind(2, EncodeJson(post))
    if InsertIntoPostCacheStmt:step() == sqlite3.DONE then
        return true
    end
    return false
end

function CleanCaches()
   local db = sqlite3.open(DB_FILE)
   db:busy_timeout(1000)
   Log(kLogVerbose, "Cleaning post cache")
   db:exec[[
   DELETE FROM
      PostCache
   WHERE
      (strftime('%s', 'now') - strftime('%s', cachedAt)) > (60 * 60 * 28);
   ]]
   Log(kLogVerbose, "Cleaning profile cache")
   db:exec[[
   DELETE FROM
      ProfileCache
   WHERE
      (strftime('%s', 'now') - strftime('%s', cachedAt)) > (60 * 60 * 28);
   ]]
   db:close()
end

local extMap = {
   xml = "rss",
   json = "jsonfeed"
}

function OnHttpRequest()
   local _, user, ext = FEED_PATH:search(GetPath())
   if user and ext then
      local feed_type = extMap[ext]
      feed.handle(user, feed_type)
      return
   end
   Route()
end

function OnWorkerStart()
   setupSql()
   -- This fails with EINVAL
   -- print(unix.getrlimit(unix.RLIMIT_AS))
   -- print(unix.getrlimit(unix.RLIMIT_RSS))
   -- print(unix.getrlimit(unix.RLIMIT_CPU))
   -- print(unix.getrusage())
   unix.setrlimit(unix.RLIMIT_AS, 400 * 1024 * 1024)
   -- assert(unix.setrlimit(unix.RLIMIT_RSS, 100 * 1024 * 1024))

   unix.setrlimit(unix.RLIMIT_CPU, 2)
   assert(unix.unveil("/tmp", "rwc"))
   assert(unix.unveil("/var/tmp", "rwc"))
   assert(unix.unveil("/etc", "r"))
   assert(unix.unveil(nil, nil))
   -- assert(unix.pledge("stdio inet dns"))
end

function OnServerHeartbeat()
   -- Clean the caches every 2 hours. Default heartbeat timer is every 5 seconds.
   -- 2 * 60 * 60 / 5 = 1440
   heartbeatCounter = (heartbeatCounter + 1) % 1440
   if heartbeatCounter == 1 then
      CleanCaches()
   end
end
