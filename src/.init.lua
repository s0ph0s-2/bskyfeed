local re = require 're'
local sqlite3 = require 'lsqlite3'
AT_URI = re.compile[[^at://(did:[a-z0-9:]+)/app.bsky.feed.post/([a-z0-9]+)]]
DB_FILE = 'bskyfeedCache.sqlite3'

function SetupDb()
    if not unix.access(DB_FILE, unix.F_OK) then
        Db = sqlite3.open(DB_FILE)
        Db:busy_timeout(1000)
        Db:exec[[PRAGMA journal_mode=WAL]]
        Db:exec[[PRAGMA synchronous=NORMAL]]
        Db:exec[[CREATE TABLE ProfileCache (
            did TEXT PRIMARY KEY,
            handle TEXT,
            displayName TEXT,
            description TEXT,
            avatar TEXT,
            cachedAt TEXT
        );]]
        Db:exec[[CREATE TABLE PostCache (
            uri TEXT PRIMARY KEY,
            postBlob BLOB,
            cachedAt TEXT
        );]]
        Db:close()
        Db = nil
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

        -- Cache cleanup query:
        -- DELETE FROM PostCache WHERE (strftime('%s', 'now') - strftime('%s', cachedAt)) > (60 * 60 * 28);
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

function OnHttpRequest()
   setupSql()
   Route()
end
