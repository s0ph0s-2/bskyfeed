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
    local identifier = string.lower(GetParam("identifier"))
    local feed_type = string.lower(GetParam("feed_type"))
    if feed_type ~= "xml" and feed_type ~= "json" then
        error({
            status = 400,
            status_msg = "Bad Request",
            headers = {},
            body = "feed_type must be either 'xml' or 'json'."
        })
        return
    end
    local no_replies = HasParam("no_replies")
    local yes_reposts = HasParam("yes_reposts")

    local did = identifier
    if identifier:sub(1, 4) ~= "did:" then
        local _, fetchedDid = Bsky.user.getHandleAndDid(identifier)
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

    local params = {}
    if no_replies then
        table.insert(params, { "no_replies" })
    end
    if yes_reposts then
        table.insert(params, { "yes_reposts" })
    end
    local visitor_url = ParseUrl(GetUrl())
    visitor_url.path = "/" .. did .. "/feed." .. feed_type
    visitor_url.params = params

    local feed_uri = EncodeUrl(visitor_url)

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
