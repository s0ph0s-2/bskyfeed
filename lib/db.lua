local CACHE_DB_FILE = "bskyfeedCache.sqlite3"

local cache_setup = [[
    PRAGMA journal_mode = WAL;
    PRAGMA busy_timeout = 5000;
    PRAGMA synchronous = NORMAL;
    PRAGMA foreign_keys = ON;

    CREATE TABLE IF NOT EXISTS ProfileCache (
        did TEXT PRIMARY KEY,
        handle TEXT,
        displayName TEXT,
        description TEXT,
        avatar TEXT,
        cachedAt TEXT
    );

    CREATE TABLE IF NOT EXISTS PostCache (
        uri TEXT PRIMARY KEY,
        postBlob BLOB,
        cachedAt TEXT
    );
]]

---@class Cache
---@field conn table
local Cache = {}

---@return Cache
function Cache:new(o)
    o = o or {}
    o.conn = Fm.makeStorage(CACHE_DB_FILE, cache_setup)
    setmetatable(o, self)
    self.__index = self
    return o
end

function Cache:getProfile(did)
    local result, err = self.conn:fetchOne(
        [[SELECT
            did, handle, displayName, description, avatar, strftime('%s', cachedAt) AS cachedAt
        FROM
            ProfileCache
        WHERE
            did = ?;]],
        did
    )
    if not result then
        return err
    end
    if result == self.conn.NONE then
        return nil
    end
end

function Cache:putProfile(did, handle, displayName, description, avatar)
    return self.conn:execute(
        [[INSERT OR REPLACE INTO ProfileCache (
            did, handle, displayName, description, avatar, cachedAt
        ) VALUES (
            ?,   ?,      ?,           ?,           ?,      datetime('now')
        );]],
        did,
        handle,
        displayName,
        description,
        avatar
    )
end

function Cache:getPost(uri)
    local result, err = self.conn:fetchOne(
        [[SELECT
            postBlob, strftime('%s', cachedAt) AS cachedAt
        FROM
            PostCache
        WHERE
            uri = ?;]],
        uri
    )
    if not result then
        return nil, err
    end
    if result == self.conn.NONE then
        return nil
    end
    return DecodeJson(result.postBlob), result.cachedAt
end

function Cache:putPost(uri, postBlob)
    if type(postBlob) ~= "string" then
        postBlob = EncodeJson(postBlob)
    end
    return self.conn:execute(
        [[INSERT OR REPLACE INTO PostCache (
            uri, postBlob, cachedAt
        ) VALUES (
            ?,   ?,        datetime('now')
        );]],
        uri,
        postBlob
    )
end

function Cache:clean(older_than_secs)
    Log(kLogVerbose, "Cleaning post cache")
    local post_ok, post_err = self.conn:execute(
        [[DELETE FROM
            PostCache
        WHERE
            (strftime('%s', 'now') - strftime('%s', cachedAt)) > ?;]],
        older_than_secs
    )
    if not post_ok then
        Log(kLogInfo, post_err)
    end
    Log(kLogVerbose, "Cleaning profile cache")
    local profile_ok, profile_err = self.conn:execute(
        [[DELETE FROM
            ProfileCache
        WHERE
            (strftime('%s', 'now') - strftime('%s', cachedAt)) > ?;]],
        older_than_secs
    )
    if not profile_ok then
        Log(kLogInfo, profile_err)
    end
end

return {
    Cache = Cache,
}
