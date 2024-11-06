local MAX_REPLY_OR_EMBED_RECURSION = 2

local function mapMentionFacet(item, facet, feature, result)
    local link = Xml.tag(
        "a", false, { href = "https://bsky.app/profile/" .. feature.did },
        Xml.text(string.sub(item.value.text, facet.index.byteStart + 1, facet.index.byteEnd))
    )
    table.insert(result, link)
end

local function mapLinkFacet(item, facet, feature, result)
    local link = Xml.tag(
        "a", false, { href = feature.uri },
        Xml.text(string.sub(item.value.text, facet.index.byteStart + 1, facet.index.byteEnd))
    )
    table.insert(result, link)
end

local function mapHashtagFacet(item, facet, feature, result)
    -- TODO: figure out what URL these are supposed to go to
    local link = Xml.tag(
        "a", false,
        Xml.text(string.sub(item.value.text, facet.index.byteStart + 1, facet.index.byteEnd))
    )
    table.insert(result, link)
end

local facetMap = {
    ["app.bsky.richtext.facet#link"] = mapLinkFacet,
    ["app.bsky.richtext.facet#mention"] = mapMentionFacet,
    ["app.bsky.richtext.facet#tag"] = mapHashtagFacet,
}

local function mapExternalEmbed(_, embed, result)
    table.insert(result, Xml.tag("hr", true))
    local preview = Xml.tag(
        "div", false,
        Xml.tag(
            "a", false, { href = embed.external.uri },
            Xml.tag("h3", false, Xml.text(embed.external.title)),
            Xml.tag(
                "span", false, { style = "font-size:0.75rem" },
                Xml.text(embed.external.uri)
            )
        ),
        Xml.tag("p", false, Xml.text(embed.external.description))
    )
    table.insert(result, preview)
end

local function mapImagesEmbed(item, embed, result)
    if not embed or not embed.images then
        Log(kLogWarn, "No images field in images embed? Item: " .. EncodeJson(item))
        return
    end
    table.insert(result, Xml.tag("hr", true))
    table.insert(result, "<div style='display:flex;flex-wrap:wrap;align-items:flex-start'>")
    local style = ""
    if #embed.images == 2 then
        style = "width:50%"
    elseif #embed.images == 3 then
        style = "width:33%"
    elseif #embed.images == 4 then
        style = "width:50%"
    end
    -- Reposts need to fetch images based on the ID of the post that has been
    -- reposted, not based on the ID of the pointer post.
    local itemBaseUri = item.uri
    if item.value.subject and item.value.subject.uri then
        itemBaseUri = item.value.subject.uri
    end
    for _, image in ipairs(embed.images) do
        local ok, src = Bsky.uri.image.feedHttp(
            itemBaseUri,
            image.image.ref["$link"]
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
            local imgTag = Xml.tag("img", true, attrs)
            table.insert(result, imgTag)
        else
            table.insert(result, Xml.tag(
                "p", false,
                Xml.text(
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

local function mapVideoEmbed(item, embed, result)
    if not embed or not embed.video then
        Log(kLogWarn, "No video field in video embed? Item: " .. EncodeJson(item))
        return
    end
    table.insert(result, Xml.tag("hr", true))
    -- Reposts need to fetch images based on the ID of the post that has been
    -- reposted, not based on the ID of the pointer post.
    local itemBaseUri = item.uri
    if item.value.subject and item.value.subject.uri then
        itemBaseUri = item.value.subject.uri
    end
    local video = embed.video
    local ok, src = Bsky.uri.image.videoPlaylist(
        itemBaseUri,
        video.ref["$link"]
    )
    local p_ok, poster = Bsky.uri.image.videoThumbnail(
        itemBaseUri,
        video.ref["$link"]
    )
    if ok and p_ok then
        local attrs = {
                alt = video.alt,
                src = src,
                poster = poster,
                loop = "true",
                controls = "true",
        }
        if embed.aspectRatio then
            attrs.width = embed.aspectRatio.width
            attrs.height = embed.aspectRatio.height
        end
        local videoTag = Xml.tag(
            "video",
            false,
            attrs,
            Xml.tag(
                "a",
                false,
                {
                    href = src
                },
                Xml.text("Download MP4 video file")
            )
        )
        table.insert(result, videoTag)
    else
        table.insert(result, Xml.tag(
            "p", false,
            Xml.text(
                "Broken video: Post("
                .. item.uri
                .. "); Image("
                .. video.ref["$link"]
                .. ")"
            )
        ))
    end
end

local embedMap = {
    ["app.bsky.embed.external"] = mapExternalEmbed,
    -- See below for mapRecordEmbed
    ["app.bsky.embed.images"] = mapImagesEmbed,
    ["app.bsky.embed.video"] = mapVideoEmbed,
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
    local displayNamePreifx = ""
    if #author.displayName > 0 then
        displayNamePreifx = Xml.tag(
            "b",
            false,
            Xml.text(author.displayName)
        ) .. Xml.tag("br", true)
    end
    return Xml.tag(
        "a", false, { href = authorProfileLink },
        displayNamePreifx,
        Xml.text("@" .. author.handle)
    )
end

--- Generate a header (HTML) for a post, used in replies and embeds.
--- @param author (Profile) Whoever wrote the post
--- @param date (string) When the post was written (RFC 3339 format)
--- @param url (string) A URL to view the post in a web browser
--- @return (string) HTML that introduces a post.
local function postHeader(author, date, url)
    local author = generateAuthorBlock(author)
    local dateRfc1123 = Date(date):fmt("${rfc1123}")
    local timeLink = Xml.tag(
        "small", false, Xml.tag(
            "a", false, { href = url }, Xml.text("Posted: " .. dateRfc1123)
        )
    )
    return author .. Xml.tag("br", true) .. timeLink
end

local function reprocessNewlines(textContent)
    -- TODO: I observed this inserting <br> into an alt="" once, this should probably be done differently.
    local paragraphs = string.gsub(textContent, "\n\n", "</p><p>")
    local breaks = string.gsub(paragraphs, "\n", "<br/>")
    return breaks
end

local function linkToSkyview(postUri)
    return Xml.tag(
        "p", false, Xml.tag(
            "i", false,
            Xml.text("("),
            Xml.tag("a", false, {
                href = Bsky.uri.assemble(
                    "https",
                    "skyview.social",
                    "/",
                    { url = postUri }
                )
            },
            Xml.text("see more on skyview.social")
        ),
        Xml.text(")")
        )
    )
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
    Log(kLogDebug, "Item: " .. EncodeJson(item))
    if item.value["$type"] == "app.bsky.feed.repost" then
        table.insert(authors, item.authorProfile)
    else
        table.insert(authors, profileData)
    end
    if item.too_deep then
        table.insert(result, linkToSkyview(itemUri))
        return table.concat(result), authors
    end
    if item.error then
        table.insert(result, Xml.tag(
            "i", false, Xml.text(item.error)
        ))
        return table.concat(result), authors
    end
    -- Replies
    if item.value and item.value.reply then
        local reply = item.value.reply
        if reply.parent.error or not reply.parent.authorProfile or reply.too_deep then
            local error = reply.parent.error
            if not error then
                table.insert(result, linkToSkyview(itemUri))
            else
                table.insert(result, Xml.tag(
                    "blockquote", false, Xml.tag(
                        "i", false, Xml.text(reply.parent.error)
                    )
                ))
            end
        else
            local quoteText, quoteAuthors = renderItemText(reply.parent, reply.parent.authorProfile, itemUri)
            local ok, quoteUrl = Bsky.uri.post.toHttp(reply.parent.uri)
            if not ok then
                quoteUrl = reply.parent.uri
            end
            local quote = Xml.tag(
                "blockquote", false,
                postHeader(reply.parent.authorProfile, reply.parent.value.createdAt, quoteUrl),
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
                        table.insert(result, Xml.text(beforeFacet))
                        facetMapper(item, facet, feature, result)
                        nextSegementStartIdx = facet.index.byteEnd + 1
                    else
                        Log(kLogWarn, "Unrecognized facet feature: " .. feature["$type"])
                    end
                end
            else
                Log(kLogWarn, "No features in facet?")
            end
        end
    end
    if item.value and item.value.text then
        table.insert(result, Xml.text(string.sub(item.value.text, nextSegementStartIdx)))
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
                Log(kLogWarn, "Unrecognized embed type: " .. embedType)
            else
                Log(kLogWarn, "Nil embed type in " .. EncodeJson(item))
            end
        end
    end
    return reprocessNewlines(table.concat(result)), authors
end

local function mapRecordEmbed(_, embed, result, authors)
    if not embed.value then
        return
    end
    local embedPost = embed.value
    local embedAuthor = embed.value.authorProfile
    local ok, embedUri = Bsky.uri.post.toHttp(embedPost.uri)
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
    table.insert(result, Xml.tag(
        "blockquote", false, postHeader(embedAuthor, embedPost.value.createdAt, embedUri), embeddedPost
    ))
end

-- This needs to be done down here because mapRecordEmbed relies on the
-- renderItemText function being defined already, which is a circular
-- dependency.
embedMap["app.bsky.embed.record"] = mapRecordEmbed
embedMap["app.bsky.embed.recordWithMedia"] = function (item, embed, result, authors)
    if embed and embed.video then
        mapVideoEmbed(item, embed, result)
    else
        mapImagesEmbed(item, embed, result)
    end
    mapRecordEmbed(item, embed, result, authors)
end

--- @alias Profile {displayName: string, description: string, avatar: string|nil, handle: string, did: string}

--- Get the profile for a user, either from the cache or from Bluesky.
--- @param user string The DID for a user.
--- @return Profile The profile data for `user`
local function getProfile(user)
    local cachedProfile = Cache:getProfile(user)
    if cachedProfile then
        local cacheAge = unix.clock_gettime() - cachedProfile.cachedAt
        if cacheAge < (60 * 60 * 24) then
            return cachedProfile
        end
    end
    local profileData, err = Bsky.xrpc.getJsonOrErr("com.atproto.repo.listRecords", {
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

    if not profileData then
        Log(kLogWarn, "Unable to fetch user profile: %s" % {err})
        return unknownUser
    end
    if #profileData.records ~= 1 then
        return unknownUser
    end
    local p = profileData.records[1]
    local handle, did = Bsky.user.getHandleAndDid(user)
    if not handle or not did then
        return unknownUser
    end
    if not p then
        Log(kLogWarn, "No records in profileData response")
        return unknownUser
    end
    if not p.value.avatar then
        Log(kLogVerbose, "No avatar field in profile?")
        return {
            displayName = p.value.displayName,
            description = p.value.description,
            handle = handle,
            did = did
        }
    end
    local avatarUri = Bsky.uri.image.profileHttp(did, p.value.avatar.ref["$link"], p.value.avatar.mimeType)
    local justTheGoodParts = {
        displayName = p.value.displayName,
        description = p.value.description,
        avatar = avatarUri,
        handle = handle,
        did = did
    }
    Cache:putProfile(
        justTheGoodParts.did,
        justTheGoodParts.handle,
        justTheGoodParts.displayName,
        justTheGoodParts.description,
        justTheGoodParts.avatar
    )
    return justTheGoodParts
end

local function fetchPost(uri)
    local cachedPost, cachedAt = Cache:getPost(uri)
    if cachedPost then
        local cacheAge = unix.clock_gettime() - cachedAt
        if cacheAge < (60 * 60 * 24) then
            -- print("fetchPost: returning cached post: " .. EncodeJson(cachedPost))
            return true, cachedPost
        end
    end
    local ok, method, params = Bsky.uri.post.toXrpcParams(uri)
    if not ok then
        return false, "(Invalid post URI)"
    end
    local postData, postErr = Bsky.xrpc.getJsonOrErr(method, params)
    if not postData then
        Log(kLogWarn, "Error fetching post: %s" % {postErr})
        return false, "(This post has been deleted)"
    end
    if not postData then
        return false, "(Invalid response from Bluesky)"
    end
    local ok3, postProfileDid = Bsky.did.fromUri(postData.uri)
    if not ok3 then
        return false, "(Invalid profile URI for parent post)"
    end
    local postProfile = getProfile(postProfileDid)
    if not postProfile then
        return false, "(The account which posted this has been deleted)"
    end
    postData.authorProfile = postProfile
    Cache:putPost(postData.uri, postData)
    return true, postData
end

local prefetchQuotePost
local prefetchReply

prefetchQuotePost = function (record, depth)
    if depth > MAX_REPLY_OR_EMBED_RECURSION then
        Log(kLogVerbose, "Recursion depth exceeded while processing " .. EncodeJson(record))
        record.too_deep = true
        return
    end
    local embed = record.value.embed
    if embed then
        if embed["$type"] == "app.bsky.embed.record" then
            Log(kLogDebug, "Processing embedded record: " .. EncodeJson(embed))
            local ok, postData = fetchPost(embed.record.uri)
            if not ok then
                embed.error = postData
            else
                embed.value = postData
                prefetchReply(embed.value, depth + 1)
                prefetchQuotePost(embed.value, depth + 1)
            end
        elseif embed["$type"] == "app.bsky.embed.recordWithMedia" then
            Log(kLogDebug, "Processing embedded record with media: " .. EncodeJson(embed))
            local ok, postData = fetchPost(embed.record.record.uri)
            if not ok then
                embed.error = postData
            else
                embed.value = postData
                embed.uri = embed.record.record.uri
                embed.images = embed.media.images
                prefetchReply(embed.value, depth + 1)
                prefetchQuotePost(embed.value, depth + 1)
            end
        else
            Log(kLogVerbose, "No prefetch required for embed type: " .. embed["$type"])
        end
    end
end

prefetchReply = function(record, depth)
    if depth > MAX_REPLY_OR_EMBED_RECURSION then
        Log(kLogVerbose, "Recursion depth exceeded while processing " .. EncodeJson(record))
        record.too_deep = true
        return
    end
    local reply = record.value.reply
    if reply then
        -- TODO: also get root?
        local ok, postData = fetchPost(reply.parent.uri)
        if not ok then
            reply.parent.error = postData
        else
            reply.parent = postData
            prefetchReply(reply.parent, depth + 1)
            prefetchQuotePost(reply.parent, depth + 1)
        end
    end
end

local function prefetchSpecialPosts(records)
    for _, record in ipairs(records) do
        prefetchReply(record, 1)
        prefetchQuotePost(record, 1)
    end
    return true
end

local function prefetchReposts(records)
    for _, item in ipairs(records) do
        local repost = item.value.subject
        if repost then
            -- print("Fetching repost data for " .. repost.uri)
            local ok, repostData = fetchPost(repost.uri)
            if not ok then
                item.error = repostData
                Log(kLogVerbose, "Repost fetch error: " .. repostData)
            else
                local originalType = item.value["$type"]
                local originallyCreatedAt = item.value.createdAt
                for key, value in pairs(repostData.value) do
                    item.value[key] = value
                end
                item.uri = repost.uri
                item.value["$type"] = originalType
                item.authorProfile = repostData.authorProfile
                item.value.createdAt = originallyCreatedAt
            end
        end
    end
end


local function handle(r, user, feedType)
    local noReplies = r.params.no_replies ~= nil
    local yesReposts = r.params.yes_reposts ~= nil
    if feedType ~= "rss" and feedType ~= "jsonfeed" then
        ServeError(400,  "Feed type must be 'rss' or 'jsonfeed', not " .. feedType)
        return
    end
    local postTable, err = Bsky.xrpc.getJsonOrErr("com.atproto.repo.listRecords",
    {
        repo = user,
        collection = "app.bsky.feed.post",
        limit = 20
    })
    if not postTable then
        Log(kLogWarn, "%s" % {err})
        Fm.serveError(500, "No response from Bluesky")
        return
    end
    -- Cache = DbUtil.Cache:new()
    -- Reposts are fetched separately (sadly). If the user asked for
    -- them, fetch them too and sort them into the same table as the
    -- regular posts.
    if yesReposts then
        -- print("Fetching reposts...")
        local repostTable, repostErr = Bsky.xrpc.getJsonOrErr(
            "com.atproto.repo.listRecords",
            {
                repo = user,
                collection = "app.bsky.feed.repost",
                limit = 20
            }
        )
        if repostTable and repostTable.records then
            -- print("Got " .. #repostTable.records .. " repost(s)")
            prefetchReposts(repostTable.records)
            for _, repost in ipairs(repostTable.records) do
                table.insert(postTable.records, repost)
            end
            local cmp = function(a, b)
                -- Sort so that the newest data is at the top of the feed.
                return a.value.createdAt > b.value.createdAt
            end
            table.sort(postTable.records, cmp)
        else
            Log(kLogWarn, "Error fetching reposts: %s" % {repostErr})
        end
    end

    if noReplies then
        local postsWithoutReplies = {}
        for _, item in ipairs(postTable.records) do
            if not item.value.reply then
                table.insert(postsWithoutReplies, item)
            end
        end
        postTable.records = postsWithoutReplies
    end
    if not prefetchSpecialPosts(postTable.records) then
        Log(kLogWarn, "Failed to prefetch posts")
        return
    end
    local profileData = getProfile(user)
    if not profileData then
        Log(kLogWarn, "Failed to fetch profile information for " .. user)
        return
    end

    Log(kLogDebug, "Full post table data: " .. EncodeJson(postTable))
    if feedType == "rss" then
        r.headers.ContentType = "application/xml; charset=utf-8"
        r.headers["x-content-type-options"] = "nosniff"
        return Fm.serveResponse(
            200,
            nil,
            Rss.render(postTable.records, profileData, renderItemText)
        )
    elseif feedType == "jsonfeed" then
        r.headers.ContentType = "application/feed+json"
        return Fm.serveResponse(
            200,
            nil,
            Jsonfeed.render(postTable.records, profileData, renderItemText)
        )
    end
end

return { handle = handle }
