local luaunit = require("third_party.luaunit")
Xml = require("xml")
Rss = require("rss")
Feed = require("feed")

TestXml = {}

function TestXml:testXmlEscapeAttrEscapesAllThreeBannedChars()
    luaunit.assertEquals(Xml.escapeAttr("&"), "&amp;")
    luaunit.assertEquals(Xml.escapeAttr("'"), "&#39;")
    luaunit.assertEquals(Xml.escapeAttr('"'), "&quot;")
end

function TestXml:testXmlEscapeAttrEscapesGnollAndVoid()
    luaunit.assertEquals(
        Xml.escapeAttr("Gnoll&Void🍖💦"),
        "Gnoll&amp;Void🍖💦"
    )
end

function TestXml:testXmlCdataEmptyStr()
    luaunit.assertEquals(Xml.cdata(""), "<![CDATA[]]>")
end

function TestXml:testXmlCdataGnollAndVoid()
    luaunit.assertEquals(
        Xml.cdata("Gnoll&Void🍖💦"),
        "<![CDATA[Gnoll&Void🍖💦]]>"
    )
end

function TestXml:testXmlCdataClosingSequenceInInput()
    luaunit.assertEquals(
        Xml.cdata("You can't have ']]>' in a CDATA block."),
        "<![CDATA[You can't have ']]]]><![CDATA[>' in a CDATA block.]]>"
    )
end

function TestXml:testXmlTagCommonTags()
    luaunit.assertEquals(Xml.tag("hr", true), "<hr/>")
    luaunit.assertEquals(Xml.tag("b", false), "<b></b>")
    luaunit.assertEquals(
        Xml.tag("link", true, { rel = "icon" }),
        "<link rel='icon'/>"
    )
end

function TestXml:testXmlTagNoChildrenWhenSelfClosing()
    luaunit.assertErrorMsgContains(
        "cannot have children",
        Xml.tag,
        "hr",
        true,
        "child"
    )
end

function TestXml:testXmlTagNoWhitespace()
    luaunit.assertErrorMsgContains("whitespace", Xml.tag, "xslt value-of", true)
end

function TestXml:testXmlTagAttrsOrFirstChildBecomesFirstChild()
    luaunit.assertEquals(
        Xml.tag("strong", false, "that's a bold move cotton"),
        "<strong>that's a bold move cotton</strong>"
    )
end

function TestXml:testXmlTagSimpleAttrsOrderedDeterministically()
    local ex1 = Xml.tag(
        "link",
        true,
        { target = "_blank", href = "https://example.com/" }
    )
    local ex2 = Xml.tag(
        "link",
        true,
        { href = "https://example.com/", target = "_blank" }
    )
    local ex3 = Xml.tag(
        "link",
        true,
        { target = "_blank", href = "https://example.com/" }
    )

    luaunit.assertEquals(ex1, ex2)
    luaunit.assertEquals(ex2, ex3)
    luaunit.assertEquals(ex3, ex1)
end

function TestXml:testXmlTagNamespacedAttrsOrderedDeterministically()
    local ex1 = Xml.tag("rss", true, {
        ["xmlns:atom"] = "http://www.w3.org/2005/Atom",
        ["xmlns:dc"] = "http://purl.org/dc/elements/1.1/",
    })
    local ex2 = Xml.tag("rss", true, {
        ["xmlns:dc"] = "http://purl.org/dc/elements/1.1/",
        ["xmlns:atom"] = "http://www.w3.org/2005/Atom",
    })
    local ex3 = Xml.tag("rss", true, {
        ["xmlns:atom"] = "http://www.w3.org/2005/Atom",
        ["xmlns:dc"] = "http://purl.org/dc/elements/1.1/",
    })

    luaunit.assertEquals(ex1, ex2)
    luaunit.assertEquals(ex2, ex3)
    luaunit.assertEquals(ex3, ex1)
end

function TestXml:testXmlTagMixedAttrsOrderedDeterministically()
    local ex1 = Xml.tag("rss", true, {
        ["xmlns:atom"] = "http://www.w3.org/2005/Atom",
        version = "2.0",
        ["xmlns:dc"] = "http://purl.org/dc/elements/1.1/",
    })
    local ex2 = Xml.tag("rss", true, {
        ["xmlns:atom"] = "http://www.w3.org/2005/Atom",
        ["xmlns:dc"] = "http://purl.org/dc/elements/1.1/",
        version = "2.0",
    })
    local ex3 = Xml.tag("rss", true, {
        version = "2.0",
        ["xmlns:atom"] = "http://www.w3.org/2005/Atom",
        ["xmlns:dc"] = "http://purl.org/dc/elements/1.1/",
    })

    luaunit.assertEquals(ex1, ex2)
    luaunit.assertEquals(ex2, ex3)
    luaunit.assertEquals(ex3, ex1)
end

-- end TestXml

local function zip(iterator1, iterator2)
    local zipIterator = function()
        return iterator1(), iterator2()
    end
    return zipIterator
end

local function iterStr(inStr)
    local index = 1
    return function()
        if index > #inStr then
            return nil
        end
        local char = inStr:sub(index, index)
        index = index + 1
        return char
    end
end

local function assertEqualsLongStr(actual, expected)
    local idx = 1
    for aChar, eChar in zip(iterStr(actual), iterStr(expected)) do
        if aChar ~= eChar then
            error(
                string.format(
                    "actual value differs from expected value starting at %s:\n%s (actual)\n         ^\n%s (expected)\n         ^",
                    idx,
                    string.sub(actual, idx - 10, idx + 2),
                    string.sub(expected, idx - 10, idx + 2)
                )
            )
        end
        idx = idx + 1
    end
end

TestRss = {}

function TestRss:setUp()
    -- Override these globals so that the test values don't change.
    GetUrlReal = GetUrl
    GetUrl = function()
        return ""
    end
    unixReal = unix
    unix = {
        clock_gettime = function()
            return 0
        end,
    }
    User_AgentReal = User_Agent
    User_Agent = "bar"
end

function TestRss:tearDown()
    GetUrl = GetUrlReal
    unix = unixReal
    User_Agent = User_AgentReal
end

function TestRss:testRssGeneratesFeedWithNoPosts()
    local profile = {
        handle = "s0ph0s.dog",
        displayName = "s0ph0s",
        did = "did:plc:asdfghjkl",
        description = "",
        avatar = "foo",
    }
    local profileUrl = "https://bsky.app/profile/" .. profile.did
    local title = profile.displayName .. " (Bluesky)"
    local rendererNotCalled = true
    local renderer = function()
        rendererNotCalled = false
    end
    local result = Rss.render({}, profile, renderer)

    luaunit.assertIsTrue(rendererNotCalled)
    assertEqualsLongStr(
        result,
        [[<?xml version="1.0" encoding="utf-8"?><?xml-stylesheet href="/rss.xsl" type="text/xsl"?><rss version='2.0' xmlns:atom='http://www.w3.org/2005/Atom' xmlns:dc='http://purl.org/dc/elements/1.1/'><channel><link>]]
            .. profileUrl
            .. [[</link><atom:link href='' rel='self' type='application/rss+xml'/><title>]]
            .. title
            .. [[</title><lastBuildDate>Thu, 01 Jan 1970 00:00:00 GMT</lastBuildDate><description>Posts on Bluesky by ]]
            .. profile.displayName
            .. [[</description><generator>bar</generator><image><url>foo</url><title>]]
            .. title
            .. [[</title><link>]]
            .. profileUrl
            .. [[</link></image></channel></rss>]]
    )
end

TestFeed = {}

function TestFeed:testRenderFeedItemTextNoFacets()
    local tests = {
        oneLine = { "one", "<p>one</p>" },
        twoLines = { "l1\nl2", "<p>l1<br/>l2</p>" },
        twoParas = { "l1\n\nl2", "<p>l1</p><p>l2</p>" },
        xss = {
            "<script>alert('pwned');</script>",
            "<p>&lt;script&gt;alert(&#39;pwned&#39;);&lt;/script&gt;</p>",
        },
    }
    for name, data in pairs(tests) do
        ---@type BskyPostView
        local input = {
            uri = "",
            cid = "",
            record = {
                text = data[1],
            },
        }
        local result = Feed.renderFeedItemText(input)
        luaunit.assertEquals(result, data[2], "Failed test " .. name)
    end
end

---@return BskyFacet
local function makeFacet(url, bstart, bend)
    return {
        features = {
            {
                ["$type"] = "app.bsky.richtext.facet#link",
                uri = url,
            },
        },
        index = {
            byteStart = bstart,
            byteEnd = bend,
        },
    }
end

function TestFeed:testRenderFeedItemTextWithFacets()
    local tests = {
        justLink = {
            "apple.com",
            { makeFacet("https://apple.com", 0, 9) },
            [[<p><a href='https://apple.com'>apple.com</a></p>]],
        },
        linkInTextWithNewline = {
            "Trying to get outta an art funk come watch\npicarto.tv/BigCozyOrca/",
            { makeFacet("https://picarto.tv/BigCozyOrca/", 43, 66) },
            [[<p>Trying to get outta an art funk come watch<br/><a href='https://picarto.tv/BigCozyOrca/'>picarto.tv/BigCozyOrca/</a></p>]],
        },
    }
    for name, data in pairs(tests) do
        ---@type BskyPostView
        local input = {
            uri = "",
            cid = "",
            author = {
                did = "did:plc:abc123",
                handle = "example.bsky.social",
            },
            record = {
                facets = data[2],
                text = data[1],
            },
        }
        local result = Feed.renderFeedItemText(input)
        luaunit.assertEquals(result, data[3], "Failed test " .. name)
    end
end

os.exit(luaunit.LuaUnit.run())
