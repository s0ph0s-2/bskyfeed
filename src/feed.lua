local xml = require "xml"
local bsky = require "bsky"
local rss = require "rss"
local jsonfeed = require "jsonfeed"


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
    -- ["app.bsky.richtext.facet#tag"] = mapHashtagFacet -- Not sure what URL to map these to
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
    table.insert(result, "<div style='display:flex;flex-wrap:wrap'>")
    local style = ""
    if #embed.images == 2 then
        style = "width:50%"
    elseif #embed.images == 3 then
        style = "width:33%"
    elseif #embed.images == 4 then
        style = "width:50%"
    end
    for _, image in ipairs(embed.images) do
        local ok, src = bsky.uri.image.feedHttp(
            item.uri,
            image.image.ref["$link"],
            image.image.mimeType
        )
        if ok then
            local attrs = {
                    alt = image.alt,
                    src = src,
                    style = style
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
    table.insert(result, "</div>")
end

local embedMap = {
    ["app.bsky.embed.external"] = mapExternalEmbed,
    -- See below for mapRecordEmbed
    ["app.bsky.embed.images"] = mapImagesEmbed
}

--- Generate an HTML author block for embeds or replies.
--- @param author (Profile) A table with displayName, handle, and did keys.
--- @return (string) HTML that describes the author.
local function generateAuthorBlock(author)
    local authorProfileLink = EncodeUrl({
        scheme = "https",
        host = "bsky.app",
        path = "/profile/" .. author.did
    })
    return xml.tag(
        "a", false, { href = authorProfileLink },
        xml.tag(
            "b", false,
            xml.text(author.displayName)
        ),
        xml.tag("br", true),
        xml.text("@" .. author.handle)
    )
end

local function reprocessNewlines(textContent)
    -- TODO: I observed this inserting <br> into an alt="" once, this should probably be done differently.
    local paragraphs = string.gsub(textContent, "\n\n", "</p><p>")
    local breaks = string.gsub(paragraphs, "\n", "<br/>")
    return breaks
end

--- Render a Bluesky record into HTML for a feed reader.
--- @param item (table) The Bluesky post/record to render.
--- @param profileData (Profile) The profile of the person who wrote the item.
--- @param itemUri (string) The HTTP URI to this post on the Bluesky web
---        interface.
--- @return (string) The HTML rendered version of the post.
--- @return (Profile[]) The authors of the post.  The primary feed author is
---         always first, followed by the profiles of people who are being
---         quoted or replied to.
local function renderItemText(item, profileData, itemUri)
    local result = {}
    local authors = {}
    table.insert(authors, profileData)
    -- Replies
    if item.value and item.value.reply then
        local reply = item.value.reply
        -- print("renderItemText: reply: " .. EncodeJson(reply))
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
            -- print("Error while trying to render " .. EncodeJson(item))
        else
            local quoteText, quoteAuthors = renderItemText(reply.parent, reply.parent.authorProfile, itemUri)
            local quote = xml.tag(
                "blockquote", false,
                generateAuthorBlock(reply.parent.authorProfile),
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
            if embedType then
                print("Unrecognized embed type: " .. embedType)
            else
                Log(kLogWarn, "Nil embed type in " .. EncodeJson(item))
            end
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
    table.insert(result, xml.tag(
        "blockquote", false, generateAuthorBlock(embedAuthor), embeddedPost
    ))
end

-- This needs to be done down here because mapRecordEmbed relies on the
-- renderItemText function being defined already, which is a circular
-- dependency.
embedMap["app.bsky.embed.record"] = mapRecordEmbed
embedMap["app.bsky.embed.recordWithMedia"] = function (item, embed, result, authors)
    mapImagesEmbed(item, embed, result)
    mapRecordEmbed(item, embed, result, authors)
end

--- @alias Profile {displayName: string, description: string, avatar: string|nil, handle: string, did: string}

--- Get the profile for a user, either from the cache or from Bluesky.
--- @param user string The DID for a user.
--- @return Profile The profile data for `user`
local function getProfile(user)
    local cachedProfile = GetProfileFromCache(user)
    if cachedProfile then
        local cacheAge = unix.clock_gettime() - cachedProfile.cachedAt
        if cacheAge < (60 * 60 * 24) then
            return cachedProfile
        end
    end
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

    if not ok or not profileData then
        return unknownUser
    end
    if #profileData.records ~= 1 then
        return unknownUser
    end
    local p = profileData.records[1]
    local handle, did = bsky.user.getHandleAndDid(user)
    if not handle or not did then
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
    PutProfileIntoCache(justTheGoodParts)
    return justTheGoodParts
end

local function fetchPost(uri)
    local cachedPost, cachedAt = GetPostFromCache(uri)
    if cachedPost then
        local cacheAge = unix.clock_gettime() - cachedAt
        if cacheAge < (60 * 60 * 24) then
            -- print("fetchPost: returning cached post: " .. EncodeJson(cachedPost))
            return true, cachedPost
        end
    end
    local ok, method, params = bsky.uri.post.toXrpcParams(uri)
    if not ok then
        print(method)
        return false, "(Invalid post URI)"
    end
    local ok2, postData = pcall(bsky.xrpc.getJsonOrErr, method, params)
    if not ok2 then
        return false, "(This post has been deleted)"
    end
    if postData == nil then
        return false, "(Invalid response from Bluesky)"
    end
    local ok3, postProfileDid = bsky.did.fromUri(postData.uri)
    if not ok3 then
        return false, "(Invalid profile URI for parent post)"
    end
    local postProfile = getProfile(postProfileDid)
    if not postProfile then
        return false, "(The account which posted this has been deleted)"
    end
    postData.authorProfile = postProfile
    PutPostIntoCache(postData)
    return true, postData
end

local function prefetchReplies(records)
    for _, item in ipairs(records) do
        local reply = item.value.reply
        if reply then
            -- TODO: also get root?
            local ok, postData = fetchPost(reply.parent.uri)
            if not ok then
                reply.parent.error = postData
            else
                reply.parent = postData
            end
        end
    end
    return true
end

local function prefetchQuotePosts(records)
    for _, item in ipairs(records) do
        local embed = item.value.embed
        if embed then
            if embed["$type"] == "app.bsky.embed.record" then
                local ok, postData = fetchPost(embed.record.uri)
                if not ok then
                    embed.error = postData
                else
                    embed.value = postData
                end
            elseif embed["$type"] == "app.bsky.embed.recordWithMedia" then
                local ok, postData = fetchPost(embed.record.record.uri)
                if not ok then
                    embed.error = postData
                else
                    embed.value = postData
                    embed.uri = embed.record.record.uri
                    embed.images = embed.media.images
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
    local noReplies = HasParam("no_replies")
    local noReposts = false
    local feedType = "rss"
    if HasParam("feed_type") then
        local requestedType = GetParam("feed_type")
        if requestedType ~= "rss" and requestedType ~= "jsonfeed" then
            error({
                status = 400,
                status_msg = "Bad Request",
                headers = {},
                body = "Feed type must be 'rss' or 'jsonfeed', not " .. requestedType
            })
            return
        end
        feedType = requestedType
    end
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

    if feedType == "rss" then
        SetHeader("Content-Type", "application/xml; charset=utf-8")
        SetHeader("x-content-type-options", "nosniff")
        Write(rss.render(bodyTable.records, profileData, renderItemText))
    elseif feedType == "jsonfeed" then
        SetHeader("Content-Type", "application/feed+json")
        Write(jsonfeed.render(bodyTable.records, profileData, renderItemText))
    end
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
