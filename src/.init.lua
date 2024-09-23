Fm = require "third_party.fullmoon"
Xml = require "xml"
Bsky = require "bsky"
Rss = require "rss"
Jsonfeed = require "jsonfeed"
Date = require "third_party.date"
DbUtil = require "db"
local about = require "about"
local re = require 're'
local feed = require "feed"
local generate = require "generate"
AT_URI = re.compile[[^at://(did:[a-z0-9:]+)/app\.bsky\.feed\.(re)?post/([a-z0-9]+)]]
FEED_PATH = re.compile[[^/([A-z0-9:\.]+)/feed\.(json|xml)$]]

---@type Cache
Cache = nil

ServerVersion = string.format(
    "%s/%s; redbean/%s",
    about.NAME,
    about.VERSION,
    about.REDBEAN_VERSION
)
ProgramBrand(ServerVersion)
ProgramCache(60 * 60 * 24 * 365, "private")

function CleanCaches()
   local cache = DbUtil.Cache:new()
   local cache_age_limit_secs = 24 * 60 * 60
   cache:clean(cache_age_limit_secs)
end

local extMap = {
   xml = "rss",
   json = "jsonfeed"
}

--[[function OnHttpRequest()
   local _, user, ext = FEED_PATH:search(GetPath())
   if user and ext then
      local feed_type = extMap[ext]
      feed.handle(user, feed_type)
      return
   end
   Route()
end]]

function OnWorkerStart()
   Cache = DbUtil.Cache:new()
   -- This fails with EINVAL
   -- print(unix.getrlimit(unix.RLIMIT_AS))
   -- print(unix.getrlimit(unix.RLIMIT_RSS))
   -- print(unix.getrlimit(unix.RLIMIT_CPU))
   -- print(unix.getrusage())
   unix.setrlimit(unix.RLIMIT_AS, 400 * 1024 * 1024)
   -- assert(unix.setrlimit(unix.RLIMIT_RSS, 100 * 1024 * 1024))

   unix.setrlimit(unix.RLIMIT_CPU, 2)
   assert(unix.unveil("/tmp", "rwc"))
   assert(unix.unveil("/var/tmp", "rwc"))
   assert(unix.unveil("/etc", "r"))
   assert(unix.unveil(nil, nil))
   -- assert(unix.pledge("stdio inet dns"))
end

local function web_setup()
   Fm.setTemplate { "/templates/", html = "fmt" }
   Fm.setRoute("/:identifier/feed.:ext", function(r)
      local feed_type = extMap[r.params.ext]
      return feed.handle(r, r.params.identifier, feed_type)
   end)
   Fm.setRoute("/rss.xsl", Fm.serveAsset)
   Fm.setRoute("/style.css", Fm.serveAsset)
   Fm.setRoute("/", function(r)
      return Fm.serveContent("index", {
         identifier = r.params.identifier,
      })
   end)
   Fm.setRoute("/generate.lua", function(r)
      return generate.handle(r)
   end)

   -- Clean the caches at minute 21 past every 2nd hour.
   Fm.setSchedule("21 */2 * * *", CleanCaches())
end

web_setup()

Fm.run()
