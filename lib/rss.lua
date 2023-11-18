local bsky = require "bsky"
local xml = require "xml"
local date = require "date"

--- Render the RSS string for the feed items.
-- @param records (table) The table of feed items to render.
-- @param profileData (table) The profile information for the primary post author for this feed.
-- @param renderItemText (function) A function which produces a string with HTML text for the feed item.
-- @return (string) XML of all of the RSS <item>s for the provided records.
local function generateItems(records, profileData, renderItemText)
    local items = {}
    for _, item in pairs(records) do
        local ok, uri = bsky.uri.post.toHttp(item.uri)
        if not ok then
            uri = item.uri
        end
        local pubDate = date(item.value.createdAt):fmt("${rfc1123}")
        local itemText, itemAuthors = renderItemText(item, profileData, uri)
        local authors = ""
        for _, author in ipairs(itemAuthors) do
            local authorStr = string.format("%s (%s)", author.displayName, author.handle)
            authors = authors .. xml.tag(
                "dc:creator", false, xml.text(authorStr)
            )
        end
        table.insert(items, xml.tag(
            "item", false,
            xml.tag("link", false, xml.text(uri)),
            xml.tag(
                "description", false,
                xml.cdata(itemText)
            ),
            xml.tag("pubDate", false, xml.text(pubDate)),
            xml.tag(
                "guid", false, { isPermaLink = "true" },
                xml.text(uri)
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
    local titleNode = xml.text(profileData.displayName .. " (Bluesky)")
    local linkNode = xml.text("https://bsky.app/profile/" .. profileData.did)
    local unixsec = unix.clock_gettime()
    output = output ..
        xml.tag(
            "rss", false, {
                version = "2.0",
                ["xmlns:atom"] = "http://www.w3.org/2005/Atom",
                ["xmlns:dc"] = "http://purl.org/dc/elements/1.1/"
            },
            xml.tag(
                "channel", false,
                xml.tag("link", false, linkNode),
                xml.tag(
                    "atom:link", true, {
                        href = GetUrl(),
                        rel = "self",
                        type = "application/rss+xml"
                    }
                ),
                xml.tag("title", false, titleNode),
                xml.tag("lastBuildDate", false, xml.text(FormatHttpDateTime(unixsec))),
                xml.tag("description", false, xml.text("Posts on Bluesky by " .. profileData.displayName)),
                xml.tag("generator", false, xml.text(User_Agent)),
                xml.tag(
                    "image", false,
                    xml.tag("url", false, xml.text(profileData.avatar)),
                    xml.tag("title", false, titleNode),
                    xml.tag("link", false, linkNode)
                ),
                generateItems(records, profileData, renderItemText)
            )
        )
    return output
end

return { render = render }
