local date = require "date"
local xml = require "xml"
local bsky = require "bsky"
local about = require "about"

local User_Agent = string.format(
    "%s/%s; redbean/%s",
    about.NAME,
    about.VERSION,
    about.REDBEAN_VERSION
)


local function mapMentionFacet(item, facet, feature, result)
    local link = xml.tag(
        "a", false, { href = "https://bsky.app/profile/" .. feature.did },
        xml.text(string.sub(item.value.text, facet.index.byteStart + 1, facet.index.byteEnd))
    )
    table.insert(result, link)
end

local function mapLinkFacet(item, facet, feature, result)
    local link = xml.tag(
        "a", false, { href = feature.uri },
        xml.text(string.sub(item.value.text, facet.index.byteStart + 1, facet.index.byteEnd))
    )
    table.insert(result, link)
end

local facetMap = {
    ["app.bsky.richtext.facet#link"] = mapLinkFacet,
    ["app.bsky.richtext.facet#mention"] = mapMentionFacet
}

local function mapExternalEmbed(_, embed, result)
    table.insert(result, xml.tag("hr", true))
    local preview = xml.tag(
        "div", false,
        xml.tag(
            "a", false, { href = embed.external.uri },
            xml.tag("h3", false, xml.text(embed.external.title)),
            xml.tag(
                "span", false, { style = "font-size:0.75rem" },
                xml.text(embed.external.uri)
            )
        ),
        xml.tag("p", false, xml.text(embed.external.description))
    )
    table.insert(result, preview)
end

local function mapImagesEmbed(item, embed, result)
    table.insert(result, xml.tag("hr", true))
    for _, image in ipairs(embed.images) do
        local ok, src = bsky.uri.image.feedHttp(
            item.uri,
            image.image.ref["$link"],
            image.image.mimeType
        )
        if ok then
            local attrs = {
                    alt = image.alt,
                    src = src
            }
            if image.aspectRatio then
                attrs.width = image.aspectRatio.width
                attrs.height = image.aspectRatio.height
            end
            local imgTag = xml.tag("img", true, attrs)
            table.insert(result, imgTag)
        else
            table.insert(result, xml.tag(
                "p", false,
                xml.text(
                    "Broken image: Post("
                    .. item.uri
                    .. "); Image("
                    .. image.image.ref["$link"]
                    .. ")"
                )
            ))
        end
    end
end

local embedMap = {
    ["app.bsky.embed.external"] = mapExternalEmbed,
    -- See below for mapRecordEmbed
    ["app.bsky.embed.images"] = mapImagesEmbed
}

local function reprocessNewlines(textContent)
    local paragraphs = string.gsub(textContent, "\n\n", "</p><p>")
    local breaks = string.gsub(paragraphs, "\n", "<br/>")
    return breaks
end

local function renderItemText(item, profileData, itemUri)
    local result = {}
    local authors = {}
    table.insert(authors, string.format("%s (%s)", profileData.displayName, profileData.handle))
    -- Replies
    if item.value and item.value.reply then
        local reply = item.value.reply
        if reply.parent.error or not reply.parent.authorProfile then
            local error = reply.parent.error
            if not error then
                table.insert(result, xml.tag(
                    "blockquote", false, xml.tag(
                        "i", false,
                        xml.text("("),
                        xml.tag("a", false, {
                            href = bsky.uri.assemble(
                                "https",
                                "skyview.social",
                                "/",
                                {
                                    url = itemUri
                                })
                            },
                            xml.text("view full reply chain on skyview.social")
                        ),
                        xml.text(")")
                    )
                ))
            end
            table.insert(result, xml.tag(
                "blockquote", false, xml.tag(
                    "i", false, xml.text(reply.parent.error)
                )
            ))
            print("Error while trying to render " .. EncodeJson(item))
        else
            local quoteText, quoteAuthors = renderItemText(reply.parent, reply.parent.authorProfile, itemUri)
            local quote = xml.tag(
                "blockquote", false,
                quoteText
            )
            table.insert(result, quote)
            for _, quoteAuthor in ipairs(quoteAuthors) do
                table.insert(authors, quoteAuthor)
            end
        end
    end
    -- Text + facets
    local nextSegementStartIdx = 1
    table.insert(result, "<p>")
    if item.value and item.value.facets then
        for _, facet in ipairs(item.value.facets) do
            if facet.features then
                -- print(EncodeJson(facet))
                for _, feature in ipairs(facet.features) do
                    local facetMapper = facetMap[feature["$type"]]
                    if facetMapper then
                        local beforeFacet = string.sub(
                            item.value.text,
                            nextSegementStartIdx,
                            facet.index.byteStart
                        )
                        table.insert(result, beforeFacet)
                        facetMapper(item, facet, feature, result)
                        nextSegementStartIdx = facet.index.byteEnd + 1
                    else
                        print("Unrecognized facet feature: " .. feature["$type"])
                    end
                end
            else
                print("no features in facet?")
            end
        end
    end
    if item.value then
        table.insert(result, string.sub(item.value.text, nextSegementStartIdx))
    end
    table.insert(result, "</p>")
    -- Embeds
    if item.value and item.value.embed then
        local embed = item.value.embed
        local embedType = embed["$type"]
        if embedMap[embedType] then
            embedMap[embedType](item, embed, result, authors)
        else
            print("Unrecognized embed type: " .. embedType)
        end
    end
    return reprocessNewlines(table.concat(result)), authors
end

local function mapRecordEmbed(_, embed, result, authors)
    local embedPost = embed.value
    local embedAuthor = embed.value.authorProfile
    local ok, embedUri = bsky.uri.post.toHttp(embedPost.uri)
    if not ok then
        embedUri = embedPost.uri
    end
    local embeddedPost, embedAuthors = renderItemText(
        embedPost,
        embedAuthor,
        embedUri
    )
    for _, author in ipairs(embedAuthors) do
        table.insert(authors, author)
    end
    table.insert(result, xml.tag("blockquote", false, embeddedPost))
end

-- This needs to be done down here because mapRecordEmbed relies on the
-- renderItemText function being defined already, which is a circular
-- dependency.
embedMap["app.bsky.embed.record"] = mapRecordEmbed

local function generateItems(records, profileData)
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
            authors = authors .. xml.tag(
                "dc:creator", false, author
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

local function getProfile(user)
    local ok, profileData = pcall(bsky.xrpc.getJsonOrErr, "com.atproto.repo.listRecords", {
        repo = user,
        limit = 1,
        collection = "app.bsky.actor.profile"
    })
    local unknownUser = {
        displayName = "Unknown User",
        description = "This user couldn't be found",
        avatar = nil,
        handle = "",
        did = user
    }

    if not ok then
        return unknownUser
    end
    if #profileData.records ~= 1 then
        return unknownUser
    end
    local p = profileData.records[1]
    local handle, did = bsky.user.getHandleAndDid(user)
    if not handle then
        return unknownUser
    end
    local avatarUri = bsky.uri.image.profileHttp(did, p.value.avatar.ref["$link"], p.value.avatar.mimeType)
    local justTheGoodParts = {
        displayName = p.value.displayName,
        description = p.value.description,
        avatar = avatarUri,
        handle = handle,
        did = did
    }
    return justTheGoodParts
end

local function prefetchReplies(records)
    for _, item in ipairs(records) do
        local reply = item.value.reply
        if reply then
            -- TODO: also get root?
            local ok, method, params = bsky.uri.post.toXrpcParams(reply.parent.uri)
            if not ok then
                print(method)
                return false
            end
            local ok3, parent_data = pcall(bsky.xrpc.getJsonOrErr, method, params)
            if not ok3 then
                reply.parent.error = "(This post has been deleted)"
            else
                if parent_data == nil then
                    return false
                else
                    local ok2, parentProfileDid = bsky.did.fromUri(parent_data.uri)
                    if not ok2 then
                        return false
                    end
                    local parentProfile = getProfile(parentProfileDid)
                    if not parentProfile then
                        return false
                    end
                    reply.parent = parent_data
                    reply.parent.authorProfile = parentProfile
                end
            end
        end
    end
    return true
end

local function prefetchQuotePosts(records)
    for _, item in ipairs(records) do
        local embed = item.value.embed
        if embed and embed["$type"] == "app.bsky.embed.record" then
            local ok, method, params = bsky.uri.post.toXrpcParams(embed.record.uri)
            if not ok then
                print(method)
                return false
            end
            local ok3, quote_data = pcall(bsky.xrpc.getJsonOrErr, method, params)
            if not ok3 then
                embed.error = "(This post has been deleted)"
            else
                if quote_data == nil then
                    return false
                else
                    local ok2, quoteProfileDid = bsky.did.fromUri(quote_data.uri)
                    if not ok2 then
                        return false
                    end
                    local quoteProfile = getProfile(quoteProfileDid)
                    if not quoteProfile then
                        return false
                    end
                    embed.value = quote_data
                    embed.value.authorProfile = quoteProfile
                end
            end
        end
    end
    return true
end

local function handle()
    if not HasParam("user") then
        SetStatus(400, "Missing required parameter 'user'")
        return
    end
    local user = GetParam("user")
    local noReplies = false
    local noReposts = false
    local bodyTable = bsky.xrpc.getJsonOrErr("com.atproto.repo.listRecords",
    {
        repo = user,
        collection = "app.bsky.feed.post",
        limit = 10
    })

    if not bodyTable then
        return
    end
    if noReplies then
        local postsWithoutReplies = {}
        for _, item in ipairs(bodyTable.records) do
            if not item.value.reply then
                table.insert(postsWithoutReplies, item)
            end
        end
        bodyTable.records = postsWithoutReplies
    else
        if not prefetchReplies(bodyTable.records) then
            return
        end
        if not prefetchQuotePosts(bodyTable.records) then

            return
        end
    end
    if noReposts then
        -- TODO: exclude reposts
        local _ = 0
    end
    local profileData = getProfile(user)
    if not profileData then
        return
    end

    local unixsec = unix.clock_gettime()
    SetHeader("Content-Type", "application/xml; charset=utf-8")
    SetHeader("x-content-type-options", "nosniff")
    Write('<?xml version="1.0" encoding="utf-8"?><?xml-stylesheet href="/rss.xsl" type="text/xsl"?>')
    local titleNode = xml.text(profileData.displayName .. " (Bluesky)")
    local linkNode = xml.text("https://bsky.app/profile/" .. user)
    Write(
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
                generateItems(bodyTable.records, profileData)
            )
        )
    )
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
-- handle()
