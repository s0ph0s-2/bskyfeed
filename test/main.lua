local luaunit = require "luaunit"
local xml = require "xml"
local rss = require "rss"

TestXml = {}

    function TestXml:testXmlEscapeAttrEscapesAllThreeBannedChars()
        luaunit.assertEquals(xml.escapeAttr("&"), "&amp;")
        luaunit.assertEquals(xml.escapeAttr("'"), "&#39;")
        luaunit.assertEquals(xml.escapeAttr('"'), "&quot;")
    end

    function TestXml:testXmlEscapeAttrEscapesGnollAndVoid()
        luaunit.assertEquals(xml.escapeAttr("Gnoll&Void🍖💦"), "Gnoll&amp;Void🍖💦")
    end

    function TestXml:testXmlCdataEmptyStr()
        luaunit.assertEquals(xml.cdata(""), "<![CDATA[]]>")
    end

    function TestXml:testXmlCdataGnollAndVoid()
        luaunit.assertEquals(xml.cdata("Gnoll&Void🍖💦"), "<![CDATA[Gnoll&Void🍖💦]]>")
    end

    function TestXml:testXmlCdataClosingSequenceInInput()
        luaunit.assertEquals(
            xml.cdata("You can't have ']]>' in a CDATA block."),
            "<![CDATA[You can't have ']]]]><![CDATA[>' in a CDATA block.]]>"
        )
    end

    function TestXml:testXmlTagCommonTags()
        luaunit.assertEquals(xml.tag("hr", true), "<hr/>")
        luaunit.assertEquals(xml.tag("b", false), "<b></b>")
        luaunit.assertEquals(
            xml.tag("link", true, { rel = "icon" }),
            "<link rel='icon'/>"
        )
    end

    function TestXml:testXmlTagNoChildrenWhenSelfClosing()
        luaunit.assertErrorMsgContains(
            "cannot have children",
            xml.tag, "hr", true, "child"
        )
    end

    function TestXml:testXmlTagNoWhitespace()
        luaunit.assertErrorMsgContains(
            "whitespace",
            xml.tag, "xslt value-of", true
        )
    end

    function TestXml:testXmlTagAttrsOrFirstChildBecomesFirstChild()
        luaunit.assertEquals(
            xml.tag("strong", false, "that's a bold move cotton"),
            "<strong>that's a bold move cotton</strong>"
        )
    end

    function TestXml:testXmlTagSimpleAttrsOrderedDeterministically()
        local ex1 = xml.tag("link", true, { target = "_blank", href = "https://example.com/"})
        local ex2 = xml.tag("link", true, { href = "https://example.com/", target = "_blank"})
        local ex3 = xml.tag("link", true, { target = "_blank", href = "https://example.com/"})

        luaunit.assertEquals(ex1, ex2)
        luaunit.assertEquals(ex2, ex3)
        luaunit.assertEquals(ex3, ex1)
    end

    function TestXml:testXmlTagNamespacedAttrsOrderedDeterministically()
        local ex1 = xml.tag("rss", true, {
            ["xmlns:atom"] = "http://www.w3.org/2005/Atom",
            ["xmlns:dc"] = "http://purl.org/dc/elements/1.1/"
        })
        local ex2 = xml.tag("rss", true, {
            ["xmlns:dc"] = "http://purl.org/dc/elements/1.1/",
            ["xmlns:atom"] = "http://www.w3.org/2005/Atom"
        })
        local ex3 = xml.tag("rss", true, {
            ["xmlns:atom"] = "http://www.w3.org/2005/Atom",
            ["xmlns:dc"] = "http://purl.org/dc/elements/1.1/"
        })

        luaunit.assertEquals(ex1, ex2)
        luaunit.assertEquals(ex2, ex3)
        luaunit.assertEquals(ex3, ex1)
    end

    function TestXml:testXmlTagMixedAttrsOrderedDeterministically()
        local ex1 = xml.tag("rss", true, {
            ["xmlns:atom"] = "http://www.w3.org/2005/Atom",
            version = "2.0",
            ["xmlns:dc"] = "http://purl.org/dc/elements/1.1/"
        })
        local ex2 = xml.tag("rss", true, {
            ["xmlns:atom"] = "http://www.w3.org/2005/Atom",
            ["xmlns:dc"] = "http://purl.org/dc/elements/1.1/",
            version = "2.0"
        })
        local ex3 = xml.tag("rss", true, {
            version = "2.0",
            ["xmlns:atom"] = "http://www.w3.org/2005/Atom",
            ["xmlns:dc"] = "http://purl.org/dc/elements/1.1/"
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
            error(string.format(
                "actual value differs from expected value starting at %s:\n%s (actual)\n         ^\n%s (expected)\n         ^",
                idx,
                string.sub(actual, idx - 10, idx + 2),
                string.sub(expected, idx - 10, idx + 2)
            ))
        end
        idx = idx + 1
    end
end

TestRss = {}

function TestRss:setUp()
    -- Override these globals so that the test values don't change.
    GetUrlReal = GetUrl
    GetUrl = function() return "" end
    unixReal = unix
    unix = {
        clock_gettime = function() return 0 end
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
    local renderer = function () rendererNotCalled = false end
    local result = rss.render({}, profile, renderer)

    print(result)
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

os.exit( luaunit.LuaUnit.run() )
