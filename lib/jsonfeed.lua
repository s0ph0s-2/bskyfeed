--
-- MARK: JSON FEED TYPES
--

--- @alias JsonFeedAuthor {name: string, url: string, avatar: string}
--- @alias JsonFeedItem {id: string, url: string, content_html: string, date_published: string, authors: JsonFeedAuthor[], language: string}

--
-- MARK: JSON FEED FUNCTIONS
--

--- Render the JSON feed items as an "array" (table).
--- @param records (table) The Bluesky records to turn into a JSON Feed.
--- @param profileData (Profile) The profile of the user whose feed is being rendered.
--- @param renderItemText (function) A function which produces a string with HTML text for the feed item.
--- @return JsonFeedItem[] The items for the feed.
local function generateItems(records, profileData, renderItemText)
    local items = {}
    -- Hint to EncodeJson that this should be serialized as an array, even if there's nothing in it.
    items[0] = false
    for _, record in pairs(records) do
        local ok, uri = Bsky.uri.post.toHttp(record.uri)
        if not ok then
            uri = record.uri
        end
        local itemText, itemAuthors = renderItemText(record, profileData, uri)
        local authors = {}
        for _, author in ipairs(itemAuthors) do
            table.insert(authors, {
                name = author.displayName .. " (" .. author.handle .. ")",
                url = Bsky.uri.profile.fromDid(author.did),
                avatar = author.avatar
            })
        end
        local item = {
            id = uri,
            url = uri,
            content_html = itemText,
            date_published = record.value.createdAt,
            authors = authors,
        }
        if record.value.langs and record.value.langs[0] then
            item.language = record.value.langs[0]
        end
        table.insert(items, item)
    end
    return items
end

--- Render the JSON Feed to a string.
--- @param records (table) The bluesky posts to render.
--- @param profileData (Profile) The profile of the user whose feed is being rendered.
--- @param renderItemText (function) A function which produces a string with HTML text for the feed item.
--- @return (string) A valid JSON instance containing JSON Feed data describing the feed.
local function render(records, profileData, renderItemText)
    local title = profileData.displayName .. " (Bluesky)"
    local profileLink = Bsky.uri.profile.fromDid(profileData.did)
    local feed = {
        version = "https://jsonfeed.org/version/1.1",
        title = title,
        home_page_url = profileLink,
        feed_url = GetUrl(),
        description = "Posts on Bluesky by " .. profileData.displayName,
        icon = profileData.avatar,
        authors = { {
            name = profileData.displayName,
            url = profileLink,
            avatar = profileData.avatar,
        } },
        items = generateItems(records, profileData, renderItemText)
    }
    return assert(EncodeJson(feed))
end

return { render = render }
