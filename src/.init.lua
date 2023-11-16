re = require 're'
sqlite3 = require 'lsqlite3'
AT_URI = re.compile[[^at://(did:[a-z0-9:]+)/app.bsky.feed.post/([a-z0-9]+)]]
DB_FILE = 'bskyfeedCache.sqlite3'

function SetupDb()
    if not unix.access(DB_FILE, unix.F_OK) then
        db = sqlite3.open(DB_FILE)
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
        db = nil
    end
end

SetupDb()

function SetupSql()
    if not db then
        db = sqlite3.open(DB_FILE)
        db:busy_timeout(1000)
        db:exec[[PRAGMA journal_mode=WAL;]]
        db:exec[[PRAGMA synchronous=NORMAL;]]
        getFromProfileCacheStmt = db:prepare[[
            SELECT
                did, handle, displayName, description, avatar, strftime('%s', cachedAt) AS cachedAt
            FROM
                ProfileCache
            WHERE
                did = ?;
        ]]
        insertIntoProfileCacheStmt = db:prepare[[
            INSERT OR REPLACE INTO ProfileCache (
                did, handle, displayName, description, avatar, cachedAt
            ) VALUES (
                ?,   ?,      ?,           ?,           ?,      datetime('now')
            );
        ]]
        getFromPostCacheStmt = db:prepare[[
            SELECT
                postBlob, strftime('%s', cachedAt) AS cachedAt
            FROM
                PostCache
            WHERE
                uri = ?;
        ]]
        insertIntoPostCacheStmt = db:prepare[[
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
    if not getFromProfileCacheStmt then
        Log(kLogWarn, 'prepare getFromProfileCache failed: ' .. db:errmsg())
        return nil
    end
    getFromProfileCacheStmt:reset()
    getFromProfileCacheStmt:bind(1, did)
    for profile in getFromProfileCacheStmt:nrows() do -- luacheck: ignore
        return profile
    end
    return nil
end

function PutProfileIntoCache(profile)
    print("PutProfileIntoCache: caching " .. EncodeJson(profile))
    if not insertIntoProfileCacheStmt then
        Log(kLogWarn, 'prepare insertIntoProfileCacheStmt failed: ' .. db:errmsg())
        return nil
    end
    insertIntoProfileCacheStmt:reset()
    insertIntoProfileCacheStmt:bind(1, profile.did)
    insertIntoProfileCacheStmt:bind(2, profile.handle)
    insertIntoProfileCacheStmt:bind(3, profile.displayName)
    insertIntoProfileCacheStmt:bind(4, profile.description)
    insertIntoProfileCacheStmt:bind(5, profile.avatar)
    if insertIntoProfileCacheStmt:step() == sqlite3.DONE then
        return true
    end
    return false
end

function GetPostFromCache(uri)
    if not getFromPostCacheStmt then
        Log(kLogWarn, 'prepare getFromPostCache failed: ' .. db:errmsg())
        return nil
    end
    getFromPostCacheStmt:reset()
    getFromPostCacheStmt:bind(1, uri)
    for post in getFromPostCacheStmt:nrows() do -- luacheck: ignore
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
    print("PutPostIntoCache: caching " .. EncodeJson(post))
    if not insertIntoPostCacheStmt then
        Log(kLogWarn, 'prepare insertIntoPostCacheStmt failed: ' .. db:errmsg())
        return nil
    end
    insertIntoPostCacheStmt:reset()
    insertIntoPostCacheStmt:bind(1, post.uri)
    insertIntoPostCacheStmt:bind(2, EncodeJson(post))
    if insertIntoPostCacheStmt:step() == sqlite3.DONE then
        return true
    end
    return false
end

function OnHttpRequest()
   SetupSql()
   Route()
end
