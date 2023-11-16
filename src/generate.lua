local bsky = require "bsky"

local function handle()
    local errors = {}
    if not HasParam("identifier") then
        table.insert(errors, "Missing required parameter 'identifier'")
    end
    if not HasParam("feed_type") then
        table.insert(errors, "Missing required parameter 'feed_type'")
    end
    if #errors > 0 then
        error({
            status = 400,
            status_msg = "Bad Request",
            headers = {},
            body = table.concat(errors, "; ")
        })
        return
    end
    local identifier = GetParam("identifier")
    local feed_type = GetParam("feed_type")
    if feed_type ~= "rss" then
        error({
            status = 400,
            status_msg = "Bad Request",
            headers = {},
            body = "Sorry, only RSS feeds are implemented so far."
        })
        return
    end
    local no_replies = HasParam("no_replies")
    local no_reposts = HasParam("no_reposts")
    if no_reposts then
        error({
            status = 400,
            status_msg = "Bad Request",
            headers = {},
            body = "Sorry, excluding posts hasn't been implemented yet."
        })
        return
    end

    local did = identifier
    if identifier:sub(1, 4) ~= "did:" then
        local _, fetchedDid = bsky.user.getHandleAndDid(identifier)
        if not fetchedDid then
            error({
                status = 404,
                status_msg = "Not Found",
                headers = {},
                body = "No user matching '"
                    .. identifier
                    .. "' could be found.  Double-check that you got the right data, then try again."
            })
            return
        end
        did = fetchedDid
    end

    local params = {
        user = did,
        feed_type = feed_type,
    }
    if no_replies then
        params.no_replies = ""
    end
    if no_reposts then
        params.no_reposts = ""
    end

    local feed_uri = bsky.uri.assemble(
        "http",
        "localhost:8080",
        "/feed.lua",
        params
    )

    SetStatus(302)
    SetHeader("Location", feed_uri)
end

local function returnError(err)
    if type(err) == "table" then
        SetStatus(err.status, err.status_msg)
        for header, value in pairs(err.headers) do
            SetHeader(header, value)
        end
        Write(err.body)
    else
        SetStatus(500)
        Write(err)
    end
end

local ok, result = xpcall(handle, debug.traceback)
if not ok then
    returnError(result)
end
