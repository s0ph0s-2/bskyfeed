VERSION := 0.5
REDBEAN_VERSION := 2.2
REDBEAN := redbean-$(REDBEAN_VERSION).com
OUTPUT := bskyfeed.com
ABOUT_FILE := lib/about.lua
LIBS := $(ABOUT_FILE) \
	lib/bsky.lua \
	lib/date.lua \
	lib/xml.lua \
	lib/rss.lua \
	lib/jsonfeed.lua
SRCS := src/.init.lua \
	src/feed.lua \
	src/generate.lua \
	src/rss.xsl \
	src/index.html \
	src/style.css

build: $(OUTPUT)

clean:
	rm $(OUTPUT) $(ABOUT_FILE)
	rm -r srv

.PHONY: build clean

$(ABOUT_FILE):
	echo "return { NAME = '$(OUTPUT)', VERSION = '$(VERSION)', REDBEAN_VERSION = '$(REDBEAN_VERSION)' }" > "$@"

srv/.lua/.dir: $(LIBS)
	mkdir -p srv/.lua
	cp $? srv/.lua/
	touch $@

srv/.dir: srv/.lua/.dir $(SRCS)
	mkdir -p srv
	cp $? srv/
	touch $@

$(OUTPUT): $(REDBEAN) srv/.dir
	rm -f $@
	cp "$(REDBEAN)" "$@"
	cd srv && zip "../$@" * .init.lua .lua/*

$(REDBEAN):
	curl -sSL "https://redbean.dev/$(REDBEAN)" -o "$(REDBEAN)" && chmod +x $(REDBEAN)
	shasum -c redbean.sums
