local function errorTag(msg)
    return Xml.tag("p", false, Xml.tag("i", false, Xml.text(msg)))
end

local function mapMentionFacet(text, feature)
    return Xml.tag(
        "a",
        false,
        { href = "https://bsky.app/profile/" .. feature.did },
        Xml.text(text)
    )
end

local function mapLinkFacet(text, feature)
    return Xml.tag("a", false, { href = feature.uri }, Xml.text(text))
end

local function mapHashtagFacet(text, feature, handle)
    local tagSearch = EncodeUrl {
        scheme = "https",
        host = "bsky.app",
        path = "/hashtag/" .. EscapePath(feature.tag),
        params = {
            { "author", handle },
        },
    }
    return Xml.tag("a", false, { href = tagSearch }, Xml.text(text))
end

local facetMap = {
    ["app.bsky.richtext.facet#link"] = mapLinkFacet,
    ["app.bsky.richtext.facet#mention"] = mapMentionFacet,
    ["app.bsky.richtext.facet#tag"] = mapHashtagFacet,
}

---@param embed BskyEmbed
---@return string
local function mapExternalEmbed(embed)
    local external = (embed.media or embed).external
    if not external then
        return errorTag("(Empty external embed?)")
    end
    ---@cast embed BskyExternalView
    return Xml.tag("hr", true)
        .. Xml.tag(
            "div",
            false,
            Xml.tag(
                "a",
                false,
                { href = external.uri },
                Xml.tag("h3", false, Xml.text(external.title)),
                Xml.tag(
                    "span",
                    false,
                    { style = "font-size:smaller" },
                    Xml.text(external.uri)
                )
            ),
            Xml.tag("p", false, Xml.text(external.description))
        )
end

---@param embed BskyEmbed
---@return string
local function mapImagesEmbed(embed)
    if not embed then
        Log(kLogWarn, "mapImagesEmbed: Nil embed")
        return ""
    end
    local images = (embed.media or embed).images
    if not images then
        Log(
            kLogWarn,
            "No images field in images embed? Embed: " .. EncodeJson(embed)
        )
        return ""
    end
    ---@cast embed BskyImagesView
    local style = ""
    if #images == 2 then
        style = "width:50%"
    elseif #images == 3 then
        style = "width:33%"
    elseif #images == 4 then
        style = "width:50%"
    end
    local imageTags = {}
    -- Reposts need to fetch images based on the ID of the post that has been
    -- reposted, not based on the ID of the pointer post.
    for i = 1, #images do
        local image = images[i]
        local attrs = {
            alt = image.alt,
            src = image.thumb,
            style = style,
        }
        if image.aspectRatio then
            attrs.width = image.aspectRatio.width
            attrs.height = image.aspectRatio.height
        end
        local imgTag = Xml.tag("img", true, attrs)
        imageTags[#imageTags + 1] = imgTag
    end
    return Xml.tag("hr", true)
        .. Xml.tag("div", false, {
            style = "display:flex;flex-wrap:wrap;align-items:flex-start",
        }, table.unpack(imageTags))
end

---@param embed BskyEmbed
---@return string
local function mapVideoEmbed(embed)
    local actualEmbed = embed
    if embed.media then
        actualEmbed = embed.media
    end
    if not actualEmbed or not actualEmbed.playlist then
        Log(
            kLogWarn,
            "No playlist field in video embed? Item: " .. EncodeJson(embed)
        )
        return ""
    end
    ---@cast embed BskyVideoView
    local attrs = {
        alt = actualEmbed.alt,
        src = actualEmbed.playlist,
        poster = actualEmbed.thumbnail,
        loop = "true",
        controls = "true",
    }
    if actualEmbed.aspectRatio then
        attrs.width = actualEmbed.aspectRatio.width
        attrs.height = actualEmbed.aspectRatio.height
    end
    local videoTag = Xml.tag(
        "video",
        false,
        attrs,
        Xml.tag("a", false, {
            href = actualEmbed.playlist,
        }, Xml.text("Download video file"))
    )
    Log(kLogDebug, videoTag)
    return Xml.tag("hr", true) .. videoTag
end

local embedMap = {
    ["app.bsky.embed.external#view"] = mapExternalEmbed,
    -- See below for mapRecordEmbed
    ["app.bsky.embed.images#view"] = mapImagesEmbed,
    ["app.bsky.embed.video#view"] = mapVideoEmbed,
}

--- Generate an HTML author block for embeds or replies.
--- @param author (Profile) A table with displayName, handle, and did keys.
--- @return (string) HTML that describes the author.
local function generateAuthorBlock(author)
    local authorProfileLink = EncodeUrl {
        scheme = "https",
        host = "bsky.app",
        path = "/profile/" .. author.did,
    }
    local displayNamePreifx = ""
    if author.displayName and #author.displayName > 0 then
        displayNamePreifx = Xml.tag(
            "b",
            false,
            Xml.text(
                #author.displayName > 0 and author.displayName or author.handle
            )
        ) .. " "
    end
    return Xml.tag(
        "a",
        false,
        { href = authorProfileLink },
        displayNamePreifx,
        Xml.text("@" .. author.handle)
    )
end

--- Generate a header (HTML) for a post, used in replies and embeds.
--- @param post BskyPostView|BskyEmbedRecordView A post.
--- @param authors BskyAuthor[]
--- @return (string) HTML that introduces a post.
local function postHeader(post, authors)
    authors[#authors + 1] = post.author
    local author = generateAuthorBlock(post.author)
    local createdAt = (post.value or post.record).createdAt
    local dateRfc1123 = Date(createdAt):fmt("${rfc1123}")
    local url = Bsky.util.atUriToWebUri(post.uri)
    local timeLink = Xml.tag(
        "small",
        false,
        Xml.tag("a", false, { href = url }, Xml.text("Posted: " .. dateRfc1123))
    )
    return author .. Xml.tag("br", true) .. timeLink
end

local function linkToSkyview(postUri)
    return Xml.tag(
        "p",
        false,
        Xml.tag(
            "i",
            false,
            Xml.text("("),
            Xml.tag("a", false, {
                href = EncodeUrl {
                    scheme = "https",
                    host = "skyview.social",
                    path = "/",
                    params = {
                        { "url", postUri },
                    },
                },
            }, Xml.text("see more on skyview.social")),
            Xml.text(")")
        )
    )
end

-- MARK: Rendering feed item text

---@enum TextStates
local TextStates = {
    text = 2,
    facet = 3,
    oneNewline = 4,
}

local function sliceSegment(text, startIdx, endIdx)
    return Xml.text(text:sub(startIdx, endIdx))
end

--- Process the post text and any facets into a string containing valid HTML markup which represents the same information.
---@param postView BskyPostView|BskyEmbedRecordView
---@return string
local function renderFeedItemText(postView)
    if not postView then
        return ""
    end
    local record = postView.value or postView.record
    if not record then
        Log(
            kLogWarn,
            "No record in feed item? Full view: " .. EncodeJson(postView)
        )
        return ""
    end
    local text = record.text
    if not text or #text < 1 then
        return ""
    end
    local output = { "<p>" }
    local facetIdx = 1
    local segmentStartIdx = 1
    local state = TextStates.text
    for byteIdx = 1, (#text + 1) do
        local chr = text:sub(byteIdx, byteIdx)
        local facet = (record.facets or {})[facetIdx]
        if state == TextStates.text then
            if chr == "\n" then
                output[#output + 1] =
                    sliceSegment(text, segmentStartIdx, byteIdx - 1)
                state = TextStates.oneNewline
            elseif facet and (byteIdx - 1) == facet.index.byteStart then
                output[#output + 1] =
                    sliceSegment(text, segmentStartIdx, byteIdx - 1)
                segmentStartIdx = byteIdx
                state = TextStates.facet
            end
        elseif state == TextStates.oneNewline then
            if chr == "\n" then
                output[#output + 1] = "</p><p>"
                segmentStartIdx = byteIdx + 1
                state = TextStates.text
            elseif facet and (byteIdx - 1) == facet.index.byteStart then
                output[#output + 1] = "<br/>"
                segmentStartIdx = byteIdx
                state = TextStates.facet
            else
                output[#output + 1] = "<br/>"
                segmentStartIdx = byteIdx
                state = TextStates.text
            end
        elseif state == TextStates.facet then
            if byteIdx == facet.index.byteEnd then
                local facetText = sliceSegment(text, segmentStartIdx, byteIdx)
                for featureIdx = 1, #facet.features do
                    local feature = facet.features[featureIdx]
                    local facetMapper = facetMap[feature["$type"]]
                    if facetMapper then
                        -- TODO: what if there are multiple features in a facet?
                        output[#output + 1] = facetMapper(
                            facetText,
                            facet.features[featureIdx],
                            postView.author.handle
                        )
                    else
                        Log(
                            kLogWarn,
                            "Unsupported facet feature: " .. feature["$type"]
                        )
                    end
                end
                segmentStartIdx = byteIdx + 1
                state = TextStates.text
                facetIdx = facetIdx + 1
            end
        end
    end
    assert(state == TextStates.text)
    output[#output + 1] = sliceSegment(text, segmentStartIdx, #text)
    output[#output + 1] = "</p>"
    return table.concat(output)
end

--- Render a Bluesky embed into HTML for a feed reader.
---@param embed BskyEmbed
---@param authors BskyAuthor
---@return string
local function renderFeedEmbed(embed, authors)
    if not embed then
        return ""
    end
    local embedType = embed["$type"]
    local embedMapper = embedMap[embedType]
    if embedMapper then
        return embedMapper(embed, authors)
    else
        Log(kLogWarn, "Unrecognized embed type: " .. tostring(embedType))
        return Xml.tag(
            "p",
            false,
            Xml.text("Unsupported embed type: " .. embedType)
        )
    end
end

---@param view BskyPostView|BskyBlockedPost|BskyNotFoundPost
---@param authors BskyAuthor[]
---@return string
local function renderFeedReplyView(view, authors)
    if view.blocked then
        return errorTag("(Blocked author.)")
    elseif view.notFound then
        return errorTag("(Post deleted.)")
    else
        ---@cast view BskyPostView
        return Xml.tag(
            "blockquote",
            false,
            postHeader(view, authors),
            renderFeedItemText(view),
            renderFeedEmbed(view.embed, authors)
        )
    end
end

---@param reply BskyReply
---@param authors BskyAuthor[]
---@return string
local function renderFeedReply(reply, authors)
    if not reply then
        return ""
    end
    if not reply.parent or not reply.parent.record then
        return ""
    end
    local result = {}
    if reply.root and reply.root.uri ~= reply.parent.uri then
        result[#result + 1] = renderFeedReplyView(reply.root, authors)
        local grandparent = reply.parent.record.reply.parent
        if grandparent and grandparent.uri ~= reply.root.uri then
            result[#result + 1] = Xml.tag("p", false, "⋮")
        end
    end
    result[#result + 1] = renderFeedReplyView(reply.parent, authors)
    return table.concat(result)
end

--- Render a Bluesky record into HTML for a feed reader.
---@param item BskyFeedItem The Bluesky post/record to render.
---@param profileData Profile the profile of the person whose feed this item came from.
---@return string # The HTML rendered version of the post.
---@return Profile[] The authors of the post.  The primary feed author is always first, followed by the profiles of the people who are being quoted or replied to.
local function renderFeedItem(item, profileData)
    local pieces = {}
    local authors = { profileData }
    -- Replies
    pieces[#pieces + 1] = renderFeedReply(item.reply, authors)
    -- Text (and facets)
    pieces[#pieces + 1] = renderFeedItemText(item.post)
    -- Embeds
    pieces[#pieces + 1] = renderFeedEmbed(item.post.embed, authors)
    -- Repost authorship
    if
        item.reason
        and item.reason["$type"] == "app.bsky.feed.defs#reasonRepost"
    then
        authors = { item.post.author }
    end
    return table.concat(pieces), authors
end

local SUPPORTED_EMBEDDED_RECORD_TYPES = {
    ["app.bsky.embed.record#viewRecord"] = true,
    ["app.bsky.embed.record#viewNotFound"] = true,
    ["app.bsky.embed.record#viewBlocked"] = true,
}
---@param embed BskyEmbed
---@return string
local function mapRecordEmbed(embed, authors)
    local record = embed.record.record or embed.record
    if not record then
        return ""
    end
    local type = record["$type"]
    if not type or not SUPPORTED_EMBEDDED_RECORD_TYPES[type] then
        return errorTag("(Unsupported embedded record type: %s)" % {
            tostring(type),
        })
    end
    -- TODO: multiple authors
    local embeddedPostParts = {}
    if record.notFound then
        embeddedPostParts[#embeddedPostParts + 1] = errorTag("(Deleted post.)")
    elseif record.blocked then
        embeddedPostParts[#embeddedPostParts + 1] = errorTag("(Blocked post.)")
    else
        embeddedPostParts[#embeddedPostParts + 1] = postHeader(record, authors)
        embeddedPostParts[#embeddedPostParts + 1] = renderFeedItemText(record)
        for i = 1, #(record.embeds or {}) do
            embeddedPostParts[#embeddedPostParts + 1] =
                renderFeedEmbed(record.embeds[i], authors)
        end
    end
    return Xml.tag("blockquote", false, table.unpack(embeddedPostParts))
end

-- This needs to be done down here because mapRecordEmbed relies on the
-- renderItemText function being defined already, which is a circular
-- dependency.
embedMap["app.bsky.embed.record#view"] = mapRecordEmbed
---@param embed BskyEmbed
---@param authors string[]
embedMap["app.bsky.embed.recordWithMedia#view"] = function(embed, authors)
    local result = ""
    if embed and embed.media.playlist then
        result = mapVideoEmbed(embed)
    elseif embed.media.external then
        result = mapExternalEmbed(embed)
    elseif embed.media.images then
        result = mapImagesEmbed(embed)
    else
        result = errorTag(
            "(Unsupported embedded media type: %s)" % { embed.media["$type"] }
        )
    end
    result = result .. mapRecordEmbed(embed, authors)
    return result
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
    local profileData, err = Bsky.getProfile(user)
    local unknownUser = {
        displayName = "Unknown User",
        description = "This user couldn't be found",
        avatar = nil,
        handle = "",
        did = user,
    }

    if not profileData then
        Log(kLogWarn, "Unable to fetch user profile: %s" % { err })
        return unknownUser
    end
    if not profileData then
        Log(kLogWarn, "No records in profileData response")
        return unknownUser
    end
    if not profileData.avatar then
        Log(kLogVerbose, "No avatar field in profile?")
        return {
            displayName = profileData.displayName,
            description = profileData.description,
            handle = profileData.handle,
            did = profileData.did,
        }
    end
    local justTheGoodParts = {
        displayName = profileData.displayName,
        description = profileData.description,
        avatar = profileData.avatar,
        handle = profileData.handle,
        did = profileData.did,
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

local VALID_FILTERS = {
    posts_no_replies = true,
    posts_with_replies = true,
    posts_with_media = true,
    posts_and_author_threads = true,
}

function table.keys(t)
    local result = {}
    for key, _ in pairs(t) do
        result[#result + 1] = key
    end
    return result
end

local function handle(r, user, feedType)
    local noReplies = r.params.no_replies ~= nil
    local noReposts = r.params.yes_reposts == nil
    local filter = r.params.filter
    if feedType ~= "rss" and feedType ~= "jsonfeed" then
        return Fm.serveError(
            400,
            "Bad Request",
            "Feed type must be 'rss' or 'jsonfeed', not " .. feedType
        )
    end
    if noReplies and filter then
        return Fm.serveError(
            400,
            "Bad Request",
            "Must provide only one of 'no_replies' and 'filter'; they conflict."
        )
    end
    if filter and not VALID_FILTERS[filter] then
        return Fm.serveError(
            400,
            "Bad Request",
            "Invalid filter '%s'. Choose one of: %s"
                % {
                    filter,
                    table.concat(table.keys(VALID_FILTERS), ", "),
                }
        )
    end
    local chosenFilter = "posts_with_replies"
    if noReplies then
        chosenFilter = "posts_no_replies"
    elseif filter then
        chosenFilter = filter
    end
    local postTable, err = Bsky.getAuthorFeed(user, {
        limit = noReposts and 40 or 20,
        filter = chosenFilter,
    })
    if not postTable then
        Log(kLogWarn, "%s" % { err })
        Fm.serveError(500, "No response from Bluesky")
        return
    end
    if noReposts then
        Log(kLogDebug, "Filtering reposts...")
        local filtered = {}
        for i = 1, #postTable.feed do
            local item = postTable.feed[i]
            if
                not item.reason
                or item.reason["$type"] ~= "app.bsky.feed.defs#reasonRepost"
            then
                filtered[#filtered + 1] = item
            end
        end
        Log(
            kLogDebug,
            "Pre-filter: %d; post-filter: %d" % { #postTable.feed, #filtered }
        )
        postTable.feed = filtered
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
            Rss.render(postTable.feed, profileData, renderFeedItem)
        )
    elseif feedType == "jsonfeed" then
        r.headers.ContentType = "application/feed+json"
        return Fm.serveResponse(
            200,
            nil,
            Jsonfeed.render(postTable.feed, profileData, renderFeedItem)
        )
    end
end

return {
    handle = handle,
    renderFeedItemText = renderFeedItemText,
}
