local luaunit = require "luaunit"
local xml = require "xml"

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

-- end TestXml

os.exit( luaunit.LuaUnit.run() )
