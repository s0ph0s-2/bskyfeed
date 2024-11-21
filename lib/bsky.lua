--- Bluesky/ATProto API wrapper layer

--- @alias HttpHeaders {[string]: string}

--- Assemble a URI from a protocol, host, path, and params.
--- Username/password and fragments are not supported.
--- @param protocol string The protocol to use for the URI (typically https)
--- @param host string The host portion of the URI (you can shoehorn
--- username/password in here too if you want, but it's not explicitly supported)
--- @param path string The path portion of the URI.
--- @param params table<string, string>|nil Parameters in the URI, if any.  URL encoding is done for you.
--- @return string A URI: "(protocol)://(host)/(path)[?(URL-encoded params)]"
local function assembleUri(protocol, host, path, params)
    local paramsStr = ""
    if params then
        local paramsPairs = {}
        for param, value in pairs(params) do
            table.insert(
                paramsPairs,
                string.format("%s=%s", EscapeParam(param), EscapeParam(value))
            )
        end
        paramsStr = "?" .. table.concat(paramsPairs, "&")
    end
    local correctedPath = path
    if path == nil then
        correctedPath = "/"
    elseif #correctedPath > 0 and string.sub(correctedPath, 1, 1) ~= "/" then
        correctedPath = "/" .. correctedPath
    end
    correctedPath = EscapePath(correctedPath)
    return string.format(
        "%s://%s%s%s",
        protocol,
        host,
        correctedPath,
        paramsStr
    )
end

--- Assemble a Bluesky/ATProto URI from the XRPC method and its parameters.
--- @param xrpc_method (string) The XRPC method to call on the Bluesky API
--- @param params (table | nil) The names and values of the parameters to pass
--- to the XRPC method.
--- @return (string) A URI that looks something like:
--- https://bsky.social/xrpc/METHOD_NAME?PARAM1=value1&PARAM2=value2
local function assembleXrpcUri(xrpc_method, params)
    if type(xrpc_method) ~= "string" then
        error(
            "assembleUri: xrpc_method must be string, not " .. type(xrpc_method)
        )
    end
    if type(params) ~= "table" and params ~= nil then
        error("assembleUri: params must be table or nil, not " .. type(params))
    end
    local result = assembleUri(
        "https",
        "public.api.bsky.app",
        "/xrpc/" .. xrpc_method,
        params
    )
    return result
end

--- Stochastically raise errors as the Bluesky rate limit is neared.
--- The hope is that this is enough back-pressure to avoid exceeding the limit.
--- @param headers (HttpHeaders) The response headers from a Bluesky API request.
--- @return (boolean) True if the request is OK, false if a rate limit is near.
local function errOnRateLimit(headers)
    if not headers then
        return true
    end
    local limit = headers["RateLimit-Limit"]
    if not limit then
        return true
    end
    local remaining = headers["RateLimit-Remaining"]
    if not remaining then
        return true
    end
    local later = "a few minutes"
    if headers["RateLimit-Reset"] then
        local rlreset = tonumber(headers["RateLimit-Reset"])
        if rlreset then
            later = FormatHttpDateTime(rlreset)
        end
    end
    local percentLeft = remaining / limit
    local random = string.byte(GetRandomBytes(1))
    local threshold = 0
    if percentLeft >= 0.5 then
        return true
    elseif percentLeft < 0.5 then
        threshold = 127
    elseif percentLeft < 0.25 then
        threshold = 63
    elseif percentLeft < 0.1 then
        threshold = 15
    elseif percentLeft < 0.05 then
        threshold = 3
    elseif percentLeft < 0.001 then
        threshold = 1
    end
    if random > threshold then
        error {
            status = 429,
            status_msg = "Too Many Requests",
            headers = {
                ["X-Bsky-RateLimit-Limit"] = limit,
                ["X-Bsky-RateLimit-Remaining"] = remaining,
            },
            body = "Please try again after " .. later .. ".",
        }
        return false
    else
        return true
    end
end

--- Make an HTTP request to the Bluesky API and decode the response JSON.
--- @param http_method string The HTTP method to use for the request (probably GET)
--- @param xrpc_method string The XRPC method to call in the Bluesky API.
--- @param params (table?) The parameters to encode in the request URI.
--- @param headers (HttpHeaders?) Headers to include in the request.
--- @param body (string?) A body to include in the request.
--- @return (number?) status The HTTP status code of the response, or -1 for invalid JSON.
--- @return (table|string) bodyOrErr If the request failed or the response was invalid, a string describing the error.  If it succeeded, a table of the headers.
--- @return (string?) resultBody If the request failed or the response was invalid, nil. If it succeeded, a string containing the response from the Bluesky API.
local function request(http_method, xrpc_method, params, headers, body)
    assert(
        type(http_method) == "string",
        "request: http_method must be a string"
    )
    assert(
        type(xrpc_method) == "string",
        "request: xrpc_method must be a string"
    )
    assert(
        type(params) == "table" or params == nil,
        "request: params must be a table or nil"
    )
    assert(
        type(headers) == "table" or headers == nil,
        "request: headers must be a table or nil, not " .. type(headers)
    )
    assert(
        type(body) == "string" or body == nil,
        "request: body must be a string or nil"
    )
    local uri = assembleXrpcUri(xrpc_method, params)
    local status, resp_headers, resp_body = Fetch(uri, {
        method = http_method,
        body = body,
        headers = headers,
    })
    if type(resp_headers) == "string" then
        return nil, resp_headers, nil
    end
    if not errOnRateLimit(resp_headers) then
        return 0, "rate limit exceeded", nil
    end
    return status, resp_headers, resp_body
end

--- Make an HTTP GET request to the Bluesky API and decode the response JSON.
--- @param method string The XRPC method to call in the Bluesky API.
--- @param params table|nil The parameters to encode in the request URI.
--- @param headers table|nil Headers to include in the request.
--- @return (number?) status The HTTP status code of the response, or -1 for invalid JSON.
--- @return (table|string) headersOrErr If the request failed or the response was invalid, a string describing the error.  If it succeeded, a table of the headers.
--- @return (string?) resultBody If the request failed or the response was invalid, nil. If it succeeded, a string containing the response from the Bluesky API.
local function get(method, params, headers)
    -- GET doesn't allow bodies.
    return request("GET", method, params, headers)
end

local function getJsonOrErr(method, params, headers)
    assert(
        type(method) == "string",
        "request: xrpc_method must be a string, not " .. type(method)
    )
    assert(
        type(params) == "table" or params == nil,
        "request: params must be a table or nil"
    )
    assert(
        type(headers) == "table" or headers == nil,
        "request: headers must be a table or nil"
    )
    local uri = assembleXrpcUri(method, params)
    local status, resp_headers, resp_body = Fetch(uri, {
        headers = headers,
    })
    if type(resp_headers) == "string" or not resp_body then
        return nil, resp_headers
    end
    if not errOnRateLimit(resp_headers) then
        return nil, "rate limit exceeded"
    end
    if status == 200 then
        local bodyObj, error = DecodeJson(resp_body)
        if not bodyObj then
            return nil, error
        else
            return bodyObj
        end
    else
        return nil, resp_body or resp_headers
    end
end

--- Convert an at:// post URI to a set of XRPC request parameters to fetch that post.
--- @param at_uri string The ATProto at://(did)/post/(post_id) URI for a post.
--- @return string|nil "ok" if the input was an expected post URI, nil otherwise
--- @return string An XRPC method name if the input was an expected post URI, or an error message otherwise.
--- @return table|nil A table of request parameters if the input was an expected post URI, nil otherwise.
local function atPostUriToXrpcPostUri(at_uri)
    local m, did, _, post_id = AT_URI:search(at_uri) -- luacheck: ignore
    if m then
        return "ok",
            "com.atproto.repo.getRecord",
            {
                repo = did,
                collection = "app.bsky.feed.post",
                rkey = post_id,
            }
    else
        return nil, "no regex matches"
    end
end

--- Split a string into two pieces at a substring split point.
--- Neither of the returned pieces contain the split point substring.
--- For example, given input_str = "image/png" and split_point = "/", the return
--- values will be "image" and "png". Multi-character substrings are allowed.
--- @param input_str (string) A string to bifurcate.
--- @param split_point (string) The substring in input_str at which to split.
--- @return (string) The portion of input_str before the split point substr.
--- @return (string) The portion of input_str after the split point substr.
local function split(input_str, split_point)
    local start_idx, end_idx = string.find(input_str, split_point, 1, true)
    return string.sub(input_str, 1, start_idx),
        string.sub(input_str, end_idx + 1)
end

--- Create an HTTP URI for an in-feed image.
--- @param post_atproto_uri (string) The at:// URI for a post.
--- @param image_id (string) The "$link" ID for an image (not cid).
--- @return (string | nil) # A string with unspecified data if the URL could be created, nil otherwise.
--- @return (string) # The desired HTTP image url if the URL could be created, unspecified string data otherwise.
local function makeFeedImageHttpUri(post_atproto_uri, image_id)
    local m, did, _, _ = AT_URI:search(post_atproto_uri) -- luacheck: ignore
    if m then
        -- local _, format = split(content_type, "/")
        return m,
            string.format(
                "https://cdn.bsky.app/img/feed_thumbnail/plain/%s/%s@%s",
                did,
                image_id,
                "jpeg"
            )
    else
        return nil, did
    end
end

--- Create an HTTP URI for a blob.
--- @param post_atproto_uri (string) The at:// URI for a post.
--- @param blob_link (string) The "$link" ID for the blob (not cid).
--- @return (string | nil) # A string with unspecified data if the URL could be created, nil otherwise.
--- @return (string) # The desired HTTP blob url if the URL could be created, unspecified string data otherwise.
local function makeBlobHttpUri(post_atproto_uri, blob_link)
    local m, did, _, _ = AT_URI:search(post_atproto_uri) -- luacheck: ignore
    if m then
        -- local _, format = split(content_type, "/")
        return m,
            assembleXrpcUri("com.atproto.sync.getBlob", {
                did = did,
                cid = blob_link,
            })
    else
        return nil, did
    end
end

--- Create an HTTP URI for an in-feed video.
--- @param post_atproto_uri (string) The at:// URI for a post.
--- @param media_id (string) The "$link" ID for a video.
--- @return (string?) # A string with unspecified data if the URL could not be created, nil otherwise.
--- @return (string) # The desired HTTP image URL if the URL could be created, unspecified string data otherwise.
local function makeVideoThumbnailHttpUri(post_atproto_uri, media_id)
    local m, did, _, _ = AT_URI:search(post_atproto_uri) -- luacheck: ignore
    if m then
        return m,
            EncodeUrl {
                scheme = "https",
                host = "video.bsky.app",
                path = "/watch/%s/%s/thumbnail.jpg" % {
                    did,
                    media_id,
                },
            }
    end
    return nil, did
end

--- Create an HTTP URI for an in-feed video's M3U8 playlist.
--- This is supposed to be obtained by querying https://public.api.bsky.app/xrpc/app.bsky.feed.getPostThread?uri=at:// and reading thread.post.embed.playlist, but the value is currently predictable and can be created by string templating the DID and media ID into a known URL. I'm going to rely on that for now to improve responsiveness.
--- @param post_atproto_uri (string) The at:// URI for a post.
--- @param media_id (string) The "$link" ID for a video.
--- @return (string?) # A string with unspecified data if the URL could not be created, nil otherwise.
--- @return (string) # The desired HTTP image URL if the URL could be created, unspecified string data otherwise.
local function makeVideoPlaylistHttpUri(post_atproto_uri, media_id)
    local m, did, _, _ = AT_URI:search(post_atproto_uri)
    if m then
        return m,
            EncodeUrl {
                scheme = "https",
                host = "video.bsky.app",
                path = "/watch/%s/%s/playlist.m3u8" % { did, media_id },
            }
    end
    return nil, did
end

--- Create an HTTP URI for a user profile image.
--- @param did (string) The DID for a user.
--- @param image_id (string) The "$link" ID for their profile image (not cid).
--- @param content_type (string) The Content-Type (MIME type) for the image.
--- @return (string) The desired HTTP image url if the URL could be created,
--- unspecified string data otherwise.
local function makeProfileImageHttpUri(did, image_id, content_type)
    local _, format = split(content_type, "/")
    return string.format(
        "https://cdn.bsky.app/img/avatar/plain/%s/%s@%s",
        did,
        image_id,
        format
    )
end

--- Get a user's DID from one of their post URIs.
--- @param uri (string) An at:// URI for a post.
--- @return (string | nil) A string if the URI was an expected post URI, nil
---         otherwise.
--- @return (string) The user's DID if the URI was an expected post URI,
---         unspecified string data otherwise.
local function getDidFromUri(uri)
    local m, did, _, _ = AT_URI:search(uri) -- luacheck: ignore
    return m, did
end

--- Get *both* a user's handle and DID given just one of them.
--- @param identifier (string) Either a user's handle (`foo.bsky.social`) or
---        their DID (`did:plc:abcdefghjkl`).
--- @return (string|nil) The user's handle, or nil if the user doesn't exist.
--- @return (string|nil) The user's DID, or nil if the user doesn't exist.
local function getHandleAndDid(identifier)
    if not identifier then
        return nil
    end
    local ok, repoDescription =
        pcall(getJsonOrErr, "com.atproto.repo.describeRepo", {
            repo = identifier,
        })
    if not ok or not repoDescription then
        return nil, nil
    end
    return repoDescription.handle, repoDescription.did
end

---@alias BskyError string

---Note that the width and height do not necessarily correspond to any unit.
---@alias BskyAspectRatio {width: integer, height: integer}

---@class BskyImagesView
---@field ["$type"] "app.bsky.embed.images#view"
---@field images {thumb: string, fullsize: string, alt: string, aspectRatio: BskyAspectRatio}[]

---@class BskyVideoView
---@field ["$type"] "app.bsky.embed.video#view"
---@field cid string
---@field playlist string
---@field thumbnail string?
---@field alt string?

---@class BskyExternalView
---@field ["$type"] "app.bsky.embed.external#view"
---@field external {uri: string, title: string, description: string, thumb: string?}

---@class BskyEmbedRecordView
---@field ["$type"] "app.bsky.embed.record#viewRecord"
---@field author BskyAuthor
---@field cid string
---@field embeds BskyEmbed[]
---@field labels BskyLabel[]
---@field uri string
---@field value BskyPostRecord

---@class BskyRecordWithMediaView
---@field ["$type"] "app.bsky.embed.recordWithMedia#view"
---@field record {record: BskyEmbedRecordView}
---@field media BskyImagesView|BskyVideoView|BskyExternalView

---@alias BskyEmbed BskyImagesView|BskyVideoView|BskyExternalView|BskyEmbedRecordView|BskyRecordWithMediaView

---@class BskyLabel
---@field ver integer
---@field src string DID of the actor which created this label
---@field uri string AT URI of the record, repository (account), or other resource that this label applies to.
---@field cid string? CID specifying the specific version of the uri resource that this label applies to.
---@field val string The short string name of the value or type of this label.
---@field neg boolean? If true, this is a negation label, which overwrites a previous label.
---@field cts string Timestamp when this label was created.
---@field exp string? Timestamp at which this label expires (no longer applies).

---@class BskyAuthor
---@field did string
---@field handle string
---@field displayName string?
---@field description string?
---@field avatar string?
---@field banner string?
---@field labels BskyLabel[]
---@field createdAt string

---@class BskyBlockedPost
---@field ["$type"] "app.bsky.feed.defs.blockedPost"
---@field blocked boolean
---@field author {did: string}

---@class BskyNotFoundPost
---@field ["$type"] "app.bsky.feed.defs.notFoundPost"
---@field notFound boolean

---@alias BskyRecord BskyPostRecord

---@alias BskyFacetFeature BskyFacetFeatureMention|BskyFacetFeatureTag|BskyFacetFeatureLink

---@class BskyFacetFeatureMention
---@field ["$type"] "app.bsky.richtext.facet#mention"
---@field did string

---@class BskyFacetFeatureTag
---@field ["$type"] "app.bsky.richtext.facet#tag"
---@field tag string

---@class BskyFacetFeatureLink
---@field ["$type"] "app.bsky.richtext.facet#link"
---@field uri string

---@class BskyFacet
---@field ["$type"] "app.bsky.richtext.facet"
---@field index {byteEnd: integer, byteStart: integer}
---@field features BskyFacetFeature[]

---@class BskyPostRecord
---@field ["$type"] "app.bsky.feed.post"
---@field createdAt string
---@field embed table
---@field facets BskyFacet[]?
---@field labels table[]
---@field langs string[]
---@field text string

---@class BskyPostView
---@field ["$type"] "app.bsky.feed.defs.postView"
---@field uri string AT URI
---@field cid string Post ID
---@field author BskyAuthor the user who posted this
---@field record BskyRecord
---@field embed BskyEmbed
---@field replyCount integer
---@field repostCount integer
---@field likeCount integer
---@field quoteCount integer
---@field labels BskyLabel[]

---@class BskyReply
---@field root BskyPostView|BskyNotFoundPost|BskyBlockedPost
---@field parent BskyPostView|BskyNotFoundPost|BskyBlockedPost

---@class BskyFeedItem
---@field post BskyPostView
---@field reply BskyReply
---@field reason table
---@field feedContext string

---@class Bsky
local Bsky = {}

---@alias getAuthorFeedOptions {limit: integer, cursor: string, filter: string, includePins: boolean}
---@param actor string An ATProto identifier.
---@param options getAuthorFeedOptions
---@return {cursor: string, feed: BskyFeedItem[]}
---@overload fun(actor: string, options: getAuthorFeedOptions): nil, BskyError
function Bsky.getAuthorFeed(actor, options)
    return getJsonOrErr("app.bsky.feed.getAuthorFeed", {
        actor = actor,
        limit = options.limit or 20,
        filter = options.filter or "posts_with_replies",
    })
end

---@param handle string AT Identifier
---@return {did: string}
---@overload fun(handle: string): nil, BskyError
function Bsky.resolveHandle(handle)
    return getJsonOrErr("com.atproto.identity.resolveHandle", {
        handle = handle,
    })
end

---@param actor string AT Identifier
---@return BskyAuthor
---@overload fun(actor: string): nil, BskyError
function Bsky.getProfile(actor)
    return getJsonOrErr("app.bsky.actor.getProfile", {
        actor = actor,
    })
end

Bsky.util = {}

--- Convert an at:// post URI to the web address of the post, suitable for web browsers. The result is a URI that a user can view in their browser using the Bluesky frontend.
---@param at_uri string The ATProto at://(did)/post/(post_id) URI for a post.
---@return string An HTTPS URI for that post on the Bluesky website, or the input if the AT URI was invalid.
function Bsky.util.atUriToWebUri(at_uri)
    local m, did, _, post_id = AT_URI:search(at_uri) -- luacheck: ignore
    if m then
        return string.format(
            "https://bsky.app/profile/%s/post/%s",
            did,
            post_id
        )
    else
        return at_uri
    end
end

--- Make an HTTP profile URI from the user's DID.
--- @param did string A Bluesky DID (`did:plc:asdfghjkl`).
--- @return string # The corresponding public bsky.app HTTPS URI for that user.
function Bsky.util.didToProfileHttpUri(did)
    return "https://bsky.app/profile/" .. did
end

return Bsky
--[[return {
    xrpc = {
        get = get,
        getJsonOrErr = getJsonOrErr
    },
    uri = {
        post = {
            toHttp = atUriToHttpUri,
            toXrpcParams = atPostUriToXrpcPostUri
        },
        image = {
            feedHttp = makeFeedImageHttpUri,
            profileHttp = makeProfileImageHttpUri,
            videoThumbnail = makeVideoThumbnailHttpUri,
            blobHttp = makeBlobHttpUri,
            videoPlaylist = makeVideoPlaylistHttpUri,
        },
        profile = {
            fromDid = makeProfileHttpUriFromDid
        },
        assemble = assembleUri
    },
    did = {
        fromUri = getDidFromUri
    },
    user = {
        getHandleAndDid = getHandleAndDid
    }
}]]
