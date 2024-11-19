--- Render the RSS string for the feed items.
---@param records BskyFeedItem[] The table of feed items to render.
---@param profileData Profile The profile information for the primary post author for this feed.
---@param renderItemText function A function which produces a string with HTML text for the feed item.
---@return string # XML of all of the RSS <item>s for the provided records.
local function generateItems(records, profileData, renderItemText)
    local items = {}
    for i = 1, #records do
        local item = records[i]
        Log(kLogDebug, "Item: " .. EncodeJson(item))
        if not item then
            return ""
        end
        local uri = Bsky.util.atUriToWebUri(item.post.uri)
        local pubDate = Date(item.post.record.createdAt):fmt("${rfc1123}")
        local itemText, itemAuthors = renderItemText(item, profileData, uri)
        local authors = ""
        for _, author in ipairs(itemAuthors) do
            local authorStr = author.handle
            if #author.displayName > 0 then
                authorStr = string.format(
                    "%s @%s",
                    author.displayName,
                    author.handle
                )
            end
            authors = authors .. Xml.tag(
                "dc:creator", false, Xml.text(authorStr)
            )
        end
        table.insert(items, Xml.tag(
            "item", false,
            Xml.tag("link", false, Xml.text(uri)),
            Xml.tag(
                "description", false,
                Xml.cdata(itemText)
            ),
            Xml.tag("pubDate", false, Xml.text(pubDate)),
            Xml.tag(
                "guid", false, { isPermaLink = "true" },
                Xml.text(uri)
            ),
            authors
        ))
    end
    return table.concat(items)
end

--- Render the RSS feed to a string.
--- @param records (table) The Bluesky posts to render.
--- @param profileData (table) The profile of the user whose feed is being
---        rendered.
--- @param renderItemText (function) A function which produces a string with
---        HTML text for the feed item.
--- @return (string) A (probably) valid XML document containing RSS data
---         describing the feed.
local function render(records, profileData, renderItemText)
    local output = '<?xml version="1.0" encoding="utf-8"?><?xml-stylesheet href="/rss.xsl" type="text/xsl"?>'
    local profileName = (#profileData.displayName > 0) and profileData.displayName or profileData.handle
    local titleNode = Xml.text(profileName .. " (Bluesky)")
    local linkNode = Xml.text("https://bsky.app/profile/" .. profileData.did)
    local unixsec = unix.clock_gettime()
    output = output ..
        Xml.tag(
            "rss", false, {
                version = "2.0",
                ["xmlns:atom"] = "http://www.w3.org/2005/Atom",
                ["xmlns:dc"] = "http://purl.org/dc/elements/1.1/"
            },
            Xml.tag(
                "channel", false,
                Xml.tag("link", false, linkNode),
                Xml.tag(
                    "atom:link", true, {
                        href = GetUrl(),
                        rel = "self",
                        type = "application/rss+xml"
                    }
                ),
                Xml.tag("title", false, titleNode),
                Xml.tag("lastBuildDate", false, Xml.text(FormatHttpDateTime(unixsec))),
                Xml.tag("description", false, Xml.text("Posts on Bluesky by " .. profileName)),
                Xml.tag("generator", false, Xml.text(User_Agent)),
                Xml.tag(
                    "image", false,
                    Xml.tag("url", false, Xml.text(profileData.avatar)),
                    Xml.tag("title", false, titleNode),
                    Xml.tag("link", false, linkNode)
                ),
                generateItems(records, profileData, renderItemText)
            )
        )
    return output
end

return { render = render }
