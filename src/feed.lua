local date = require("date")

-- local HOST = "bskyatom.s0ph0s.dog"

local function escapeAttr(value)
    return string.gsub(value, '["\']', { ["'"] = "&#39;", ['"'] = "&quot;" })
end

local function text(value)
    return EscapeHtml(value)
end

local function cdata(value)
    local no_gt = string.gsub(value, "]]>", "]]&gt;")
    return string.format("<![CDATA[%s]]>", no_gt)
end

local function tag(tagName, selfClosing, attrsOrFirstChild, ...)
    local children = { ... }

    if not tagName or type(tagName) ~= "string" or #tagName == 0 then
        error("tag: tagName is not a string (or is emptystr)")
    end
    if string.match(tagName, "%s") then
        error("tag: tagName cannot contain whitespace")
    end
    if selfClosing and (#children > 0 or type(attrsOrFirstChild) == "string") then
        error("tag: self closing tags cannot have children")
    end

    local attrs = {}
    if type(attrsOrFirstChild) == "string" then
        table.insert(children, 1, attrsOrFirstChild)
        attrsOrFirstChild = {}
    end
    if attrsOrFirstChild ~= nil and type(attrsOrFirstChild) == "table" then
        for key, value in pairs(attrsOrFirstChild) do
            if type(value) ~= "boolean" then
                table.insert(
                    attrs,
                    string.format(' %s="%s"', key, escapeAttr(value))
                )
            elseif value then
                table.insert(attrs, " " .. key)
            end
        end
    end

    local opening = string.format("<%s%s", tagName, table.concat(attrs))
    if selfClosing then
        return opening .. "/>"
    else
        return string.format("%s>%s</%s>", opening, table.concat(children), tagName)
    end
end

local function atUriToHttpUri(string)
    local m, did, post_id = AT_URI:search(string) -- luacheck: ignore
    if m then
        return "ok", string.format("https://bsky.app/profile/%s/post/%s", did, post_id)
    else
        return nil, did
    end
end

local function atPostUriToXrpcPostUri(string)
    local m, did, post_id = AT_URI:search(string) -- luacheck: ignore
    if m then
        return "ok", string.format(
            "https://bsky.social/xrpc/com.atproto.repo.getRecord?repo=%s&collection=app.bsky.feed.post&rkey=%s",
            did,
            post_id
        )
    else
        return nil, did
    end
end

local function split(input_str, split_point)
    local start_idx, end_idx = string.find(input_str, split_point, 1, true)
    return string.sub(input_str, 1, start_idx), string.sub(input_str, end_idx + 1)
end

local function makeFeedImageHttpUri(post_atproto_uri, image_id, content_type)
    local m, did, _ = AT_URI:search(post_atproto_uri) -- luacheck: ignore
    if m then
        local _, format = split(content_type, "/")
        return m, string.format(
            "https://cdn.bsky.app/img/feed_thumbnail/plain/%s/%s@%s",
            did,
            image_id,
            format
        )
    else
        return nil, did
    end
end

local function makeProfileImageHttpUri(did, image_id, content_type)
    local _, format = split(content_type, "/")
    return string.format(
        "https://cdn.bsky.app/img/avatar/plain/%s/%s@%s",
        did,
        image_id,
        format
    )
end

local function getDidFromUri(uri)
    local m, did, _ = AT_URI:search(uri) -- luacheck: ignore
    return m, did
end

local function mapMentionFacet(item, facet, feature, result)
    local link = tag(
        "a", false, { href = "https://bsky.app/profile/" .. feature.did },
        text(string.sub(item.value.text, facet.index.byteStart + 1, facet.index.byteEnd))
    )
    table.insert(result, link)
end

local function mapLinkFacet(item, facet, feature, result)
    local link = tag(
        "a", false, { href = feature.uri },
        text(string.sub(item.value.text, facet.index.byteStart + 1, facet.index.byteEnd))
    )
    table.insert(result, link)
end

local facetMap = {
    ["app.bsky.richtext.facet#link"] = mapLinkFacet,
    ["app.bsky.richtext.facet#mention"] = mapMentionFacet
}

local function mapExternalEmbed(_, embed, result)
    table.insert(result, tag("hr", true))
    local preview = tag(
        "div", false,
        tag(
            "a", false, { href = embed.external.uri },
            tag("h3", false, text(embed.external.title)),
            tag(
                "span", false, { style = "font-size:0.75rem" },
                text(embed.external.uri)
            )
        ),
        tag("p", false, text(embed.external.description))
    )
    table.insert(result, preview)
end

local function mapImagesEmbed(item, embed, result)
    table.insert(result, tag("hr", true))
    for _, image in ipairs(embed.images) do
        local ok, src = makeFeedImageHttpUri(
            item.uri,
            image.image.ref["$link"],
            image.image.mimeType
        )
        if ok then
            local imgTag = tag(
                "img", true, {
                    alt = image.alt,
                    height = image.aspectRatio.height,
                    width = image.aspectRatio.width,
                    src = src
                }
            )
            table.insert(result, imgTag)
        else
            table.insert(result, tag(
                "p", false,
                text(
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
    -- Quote tweet? ["app.bsky.embed.record"] = mapRecordEmbed,
    ["app.bsky.embed.images"] = mapImagesEmbed
}

local function reprocessNewlines(textContent)
    local paragraphs = string.gsub(textContent, "\n\n", "</p><p>")
    local breaks = string.gsub(paragraphs, "\n", "<br/>")
    return breaks
end

local function renderItemText(item, profileData)
    local result = {}
    local author = string.format("%s (%s)", profileData.displayName, profileData.handle)
    -- Replies
    if item.value and item.value.reply then
        local reply = item.value.reply
        if reply.parent.error or not reply.parent.authorProfile then
            local error = reply.parent.error
            if not error then
                table.insert(result, tag(
                    "blockquote", false, tag(
                        "i", false, text("(more replies)")
                    )
                ))
            end
            table.insert(result, tag(
                "blockquote", false, tag(
                    "i", false, text(reply.parent.error)
                )
            ))
            print("Error while trying to render " .. EncodeJson(item))
        else
            local quoteText, quoteAuthor = renderItemText(reply.parent, reply.parent.authorProfile)
            local quote = tag(
                "blockquote", false,
                quoteText
            )
            table.insert(result, quote)
            author = author .. ", replying to " .. quoteAuthor
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
            embedMap[embedType](item, embed, result)
        else
            print("Unrecognized embed type: " .. embedType)
        end
    end
    return reprocessNewlines(table.concat(result)), author
end

local function generateItems(records, profileData)
    local items = {}
    for _, item in pairs(records) do
        local ok, uri = atUriToHttpUri(item.uri)
        if not ok then
            uri = item.uri
        end
        local pubDate = date(item.value.createdAt):fmt("${rfc1123}")
        local itemText, author = renderItemText(item, profileData)
        table.insert(items, tag(
            "item", false,
            tag("link", false, text(uri)),
            tag(
                "description", false,
                cdata(itemText)
            ),
            tag("pubDate", false, text(pubDate)),
            tag(
                "guid", false, { isPermaLink = "true" },
                text(uri)
            ),
            tag("author", false, text(author))
        ))
    end
    return table.concat(items)
end

local function fetchDecodeBskyUri(uri, substituteTable)
    local failHard = false
    if substituteTable == nil then
        failHard = true
    end
    local status, _, body = Fetch(uri)
    if status ~= 200 and failHard then
        SetStatus(503, "Bluesky API error")
        SetHeader("Content-Type", "application/json")
        SetHeader("X-Bsky-Uri", uri)
        Write(body)
        return nil
    elseif status ~= 200 and not failHard then
        return substituteTable
    end
    return DecodeJson(body)
end

local function getHandleAndDid(identifier)
    if not identifier then
        return nil
    end
    local descriptionUri = (
        "https://bsky.social/xrpc/com.atproto.repo.describeRepo?repo="
        .. identifier
    )
    local repoDescription = fetchDecodeBskyUri(descriptionUri, { handle = "missing", did = "missing" })
    if not repoDescription then
        return nil, nil
    end
    return repoDescription.handle, repoDescription.did
end

local function getProfile(user)
    local profileUri = (
        "https://bsky.social/xrpc/com.atproto.repo.listRecords?repo="
        .. user
        .. "&limit=1&collection=app.bsky.actor.profile"
    )
    local profileData = fetchDecodeBskyUri(profileUri, "error")
    local unknownUser = {
        displayName = "Unknown User",
        description = "This user couldn't be found",
        avatar = nil,
        handle = "",
        did = user
    }

    if not profileData then
        return unknownUser
    end
    if profileData == "error" then
        return unknownUser
    end
    if #profileData.records ~= 1 then
        return unknownUser
    end
    local p = profileData.records[1]
    local handle, did = getHandleAndDid(user)
    if not handle then
        return unknownUser
    end
    local avatarUri = makeProfileImageHttpUri(did, p.value.avatar.ref["$link"], p.value.avatar.mimeType)
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
            local ok, parent_uri = atPostUriToXrpcPostUri(reply.parent.uri)
            if not ok then
                print(parent_uri)
                return false
            end
            local parent_data = fetchDecodeBskyUri(parent_uri, "error")
            if parent_data == nil then
                return false
            end
            if parent_data == "error" then
                reply.parent.error = "(This post has been deleted)"
            else
                local ok2, parentProfileDid = getDidFromUri(parent_data.uri)
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
    return true
end

local function foo()
    if not HasParam("user") then
        SetStatus(400, "Missing required parameter 'user'")
        return
    end
    local user = GetParam("user")
    local noReplies = false
    local noReposts = false
    local bodyTable = fetchDecodeBskyUri(
        "https://bsky.social/xrpc/com.atproto.repo.listRecords?repo="
        .. user
        .. "&collection=app.bsky.feed.post&limit=10",
        true
    )

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
    local titleNode = text(profileData.displayName .. " (Bluesky)")
    local linkNode = text("https://bsky.app/profile/" .. user)
    Write(
        tag(
            "rss", false, { version = "2.0" },
            tag(
                "channel", false,
                tag("link", false, linkNode),
                tag("title", false, titleNode),
                tag("lastBuildDate", false, text(FormatHttpDateTime(unixsec))),
                tag("description", false, text("Posts on Bluesky by " .. user)),
                -- TODO: make these constants somewhere instead of hard-coding them
                tag("generator", false, text("bskyfeed/0.5; redbean/2.2")),
                tag(
                    "image", false,
                    tag("url", false, text(profileData.avatar)),
                    tag("title", false, titleNode),
                    tag("link", false, linkNode)
                ),
                generateItems(bodyTable.records, profileData)
            )
        )
    )
end

foo()
