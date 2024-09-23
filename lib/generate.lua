local function handle(r)
    local errors = {}
    local identifier = r.params.identifier
    if not identifier then
        table.insert(errors, "Missing required parameter 'identifier'")
    end
    local feed_type = r.params.feed_type
    if not feed_type then
        table.insert(errors, "Missing required parameter 'feed_type'")
    end
    if #errors > 0 then
        return Fm.serveError(400, "Bad Request", table.concat(errors, "; "))
    end
    identifier = string.lower(identifier)
    feed_type = string.lower(feed_type)
    if feed_type ~= "xml" and feed_type ~= "json" then
        return Fm.serveError(400, "Bad Request", "feed_type must be either 'xml' or 'json'.")
    end
    local no_replies = r.params.no_replies ~= nil
    local yes_reposts = r.params.yes_reposts ~= nil

    local did = identifier
    if identifier:sub(1, 4) ~= "did:" then
        local _, fetchedDid = Bsky.user.getHandleAndDid(identifier)
        if not fetchedDid then
            return Fm.serveError(
                404,
                "Not Found",
                "No user matching %s could be found. Double-check that you got the right data, then try again." % { identifier })
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
    local visitor_url = ParseUrl(r.url)
    visitor_url.path = "/" .. did .. "/feed." .. feed_type
    visitor_url.params = params

    local feed_uri = EncodeUrl(visitor_url)

    return Fm.serveRedirect(302, feed_uri)
end

return {
    handle = handle,
}
