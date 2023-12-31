# Bluesky Feed

Generate RSS feeds from arbitrary users' Bluesky posts.

# FAQ

## Why did you make this?

I tremendously appreciate what [kawarimidoll](https://github.com/kawarimidoll) has built with [bluestream](https://github.com/kawarimidoll/bluestream), but there are a few ways in which I wish it worked differently. So I built my own! (Also I wanted an excuse to write Lua Server Pages for [Redbean](https://redbean.dev)).

## Why not Atom?

Atom feeds require every entry to have a title. For a social media service where posts do not include titles, this restriction means I have to manufacture data to put in the title slot. This data is either redundant, or it receives undue visual weight in most feed readers. RSS does not impose this restriction, so I've chosen to use that instead.

# Usage

1. Clone this repo
2. `cd bskyfeed`
3. `make`
4. Run `bskyfeed.com`
5. Open `http://localhost:8080`

# Planned enhancements

- [x] Filtering out replies and reposts

  - Somewhat more complicated than it seems, because I want to make sure the feed still has 10 items in it after the filtering, if possible.

- [x] Build the landing page that explains what it is and offers a convenient text box to make feed URLs
- Refactor the spaghetti into something more maintainable
  - [x] Move library functions out of `feed.lua` and into modules
  - [x] Build a (very thin) API wrapper for atproto calls so that I don't need to do so much string concatenation
  - [ ] Separate the data fetches from the processing from the feed generation more cleanly
- [x] [JSON Feed](https://www.jsonfeed.org) output support (enables profile pictures to show up as feed author icons, at least in NetNewsWire)
- [ ] Find a way to make the `Fetch` requests asynchronously, to improve load times
  - Probably going to be difficult; the only way I can find to accomplish this is by forking and running the `Fetch` in another process. Then you have to do XPC somehow, which is difficult.
  - Also less necessary now that I've implemented caching; only the initial load is slow (which is probably fine)
- [ ] Handle errors better (also pretty disorganized right now)
- [x] Cache user profiles and quote/embed posts in a sqlite database so that fetches for those can be skipped most of the time.
- [x] Implement rate-limiting based on the metadata returned in headers from Bluesky about how many requests are left in this period.
- [ ] Use Redbean's benchmarking facilities to help optimize performance.
- [x] Tweak the XSLT template to fix the stretched images, etc.
- [x] When there is a longer reply chain, link to skyview.social instead of just saying "(more replies)"
- [x] Support quote posts.
- [x] Enhance embed/reply code to show display name and handle of the author of embedded/replied text.
- [x] Clean up the cache once in a while (maybe using `OnServerHeartbeat`?)

# Support/Maintenance Guarantees

None, sorry :(

# License

I dunno yet, I'll figure it out later.
