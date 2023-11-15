--- Bluesky/ATProto API wrapper layer

--- Assemble a Bluesky/ATProto URI from the XRPC method and its parameters.
-- @param xrpc_method (string) The XRPC method to call on the Bluesky API
-- @param params (table | nil) The names and values of the parameters to pass to
--        the XRPC method.
-- @return (string) A URI that looks something like:
--         https://bsky.social/xrpc/METHOD_NAME?PARAM1=value1&PARAM2=value2
local function assembleUri(xrpc_method, params)
    if type(xrpc_method) ~= "string" then
        error("assembleUri: xrpc_method must be string, not " .. type(xrpc_method))
    end
    if type(params) ~= "table" and params ~= nil then
        error("assembleUri: params must be table or nil, not " .. type(params))
    end
    local paramsStr = ""
    if params then
        local paramsPairs = {}
        for param, value in pairs(params) do
            table.insert(paramsPairs, string.format(
                "%s=%s",
                EscapeParam(param),
                EscapeParam(value)
            ))
        end
        paramsStr = table.concat(paramsPairs, "&")
    end
    local result = string.format(
        "https://bsky.social/xrpc/%s?%s",
        xrpc_method,
        paramsStr
    )
    return result
end

--- Make an HTTP request to the Bluesky API and decode the response JSON.
-- @param http_method (string) The HTTP method to use for the request (probably GET)
-- @param xrpc_method (string) The XRPC method to call in the Bluesky API.
-- @param params (table | nil) The parameters to encode in the request URI.
-- @param headers (table | nil) Headers to include in the request.
-- @param body (string | nil) A body to include in the request.
-- @return (number) The HTTP status code of the response, or -1 for invalid JSON.
-- @return (table | string) If the request failed or the response was invalid, a
--         string describing the error.  If it succeeded, a table of the headers.
-- @return (table | nil) If the request failed or the response was invalid, nil.
--         If it succeeded, a table containing the JSON-decoded response from
--         the Bluesky API.
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
    local uri = assembleUri(xrpc_method, params)
    return Fetch(uri, {
        method = http_method,
        body = body,
        headers = headers
    })
end

--- Make an HTTP GET request to the Bluesky API and decode the response JSON.
-- @param xrpc_method (string) The XRPC method to call in the Bluesky API.
-- @param params (table | nil) The parameters to encode in the request URI.
-- @param headers (table | nil) Headers to include in the request.
-- @return (number) The HTTP status code of the response, or -1 for invalid JSON.
-- @return (table | string) If the request failed or the response was invalid, a
--         string describing the error.  If it succeeded, a table of the headers.
-- @return (table | nil) If the request failed or the response was invalid, nil.
--         If it succeeded, a table containing the JSON-decoded response from
--         the Bluesky API.
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
    local uri = assembleUri(method, params)
    local status, resp_headers, resp_body = Fetch(uri, {
        headers = headers
    })
    if status == 200 then
        local bodyObj, error = DecodeJson(resp_body)
        if not bodyObj then
            error({
                status = 502,
                status_msg = error,
                headers = {
                    ["X-Bsky-Uri"] = uri
                },
                body = resp_body
            })
            return nil
        else
            return bodyObj
        end
    else
        error({
            status = status,
            status_msg = nil,
            headers = {
                ["X-Bsky-Uri"] = uri
            },
            body = resp_body or resp_headers
        })
        return nil
    end
end

--- Convert an at:// post URI to an HTTP URI suitable for web browsers.
-- The result is a URI that a user can view in their browser using the Bluesky
-- frontend.
-- @param at_uri (string) The ATProto at://(did)/post/(post_id) URI for a post.
-- @return (string | nil) "ok" if the input was an expected post URI, nil otherwise.
-- @return (string) An HTTPS URI for that post on the Bluesky website, or garbage otherise.
local function atUriToHttpUri(at_uri)
    local m, did, post_id = AT_URI:search(at_uri) -- luacheck: ignore
    if m then
        return "ok", string.format("https://bsky.app/profile/%s/post/%s", did, post_id)
    else
        return nil, did
    end
end

--- Convert an at:// post URI to a set of XRPC request parameters to fetch that post.
-- @param at_uri (string) The ATProto at://(did)/post/(post_id) URI for a post.
-- @return (string | nil) "ok" if the input was an expected post URI, nil otherwise
-- @return (string) An XRPC method name if the input was an expected post URI, or an error message otherwise.
-- @return (table | nil) A table of request parameters if the input was an expected post URI, nil otherwise.
local function atPostUriToXrpcPostUri(at_uri)
    local m, did, post_id = AT_URI:search(at_uri) -- luacheck: ignore
    if m then
        return "ok", "com.atproto.repo.getRecord", {
            repo = did,
            collection = "app.bsky.feed.post",
            rkey = post_id
        }
    else
        return nil, "no regex matches"
    end
end

--- Split a string into two pieces at a substring split point.
-- Neither of the returned pieces contain the split point substring.
-- For example, given input_str = "image/png" and split_point = "/", the return
-- values will be "image" and "png". Multi-character substrings are allowed.
-- @param input_str (string) A string to bifurcate.
-- @param split_point (string) The substring in input_str at which to split.
-- @return (string) The portion of input_str before the split point substr.
-- @return (string) The portion of input_str after the split point substr.
local function split(input_str, split_point)
    local start_idx, end_idx = string.find(input_str, split_point, 1, true)
    return string.sub(input_str, 1, start_idx), string.sub(input_str, end_idx + 1)
end

--- Create an HTTP URI for an in-feed image.
-- @param post_atproto_uri (string) The at:// URI for a post.
-- @param image_id (string) The "$link" ID for an image (not cid).
-- @param content_type (string) The Content-Type (MIME type) for the image.
-- @return (string | nil) A string with unspecified data if the URL could be created, nil otherwise.
-- @return (string) The desired HTTP image url if the URL could be created, unspecified string data otherwise.
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

--- Create an HTTP URI for a user profile image.
-- @param did (string) The DID for a user.
-- @param image_id (string) The "$link" ID for their profile image (not cid).
-- @param content_type (string) The Content-Type (MIME type) for the image.
-- @return (string | nil) A string with unspecified data if the URL could be created, nil otherwise.
-- @return (string) The desired HTTP image url if the URL could be created, unspecified string data otherwise.
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
-- @param uri (string) An at:// URI for a post.
-- @return (string | nil) A string if the URI was an expected post URI, nil otherwise.
-- @return (string) The user's DID if the URI was an expected post URI, unspecified string data otherwise.
local function getDidFromUri(uri)
    local m, did, _ = AT_URI:search(uri) -- luacheck: ignore
    return m, did
end

return {
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
            profileHttp = makeProfileImageHttpUri
        }
    },
    did = {
        fromUri = getDidFromUri
    }
}
