VERSION := 0.5
REDBEAN_VERSION := 3.0beta
REDBEAN := redbean-$(REDBEAN_VERSION).com
OUTPUT := bskyfeed.com
ABOUT_FILE := lib/about.lua
LIBS := $(ABOUT_FILE) \
	lib/bsky.lua \
	lib/date.lua \
	lib/xml.lua \
	lib/rss.lua \
	lib/feed.lua \
	lib/jsonfeed.lua
SRCS := src/.init.lua \
	src/generate.lua \
	src/rss.xsl \
	src/index.html \
	src/style.css
TEST_LIBS := lib/luaunit.lua

build: $(OUTPUT)

clean:
	rm $(OUTPUT) $(ABOUT_FILE) test-$(REDBEAN)
	rm -r srv srv-test

test: test-$(REDBEAN)
	./$< -i test/main.lua

.PHONY: build clean test

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

srv-test/.lua/.dir: $(LIBS) $(TEST_LIBS)
	mkdir -p srv-test/.lua
	cp $? srv-test/.lua/
	touch $@

srv-test/.dir: srv-test/.lua/.dir $(SRCS)
	mkdir -p srv-test
	cp $? srv-test/
	touch $@

$(OUTPUT): $(REDBEAN) srv/.dir
	rm -f $@
	cp "$(REDBEAN)" "$@"
	cd srv && zip "../$@" * .init.lua .lua/*

$(REDBEAN):
	curl -sSL "https://redbean.dev/$(REDBEAN)" -o "$(REDBEAN)" && chmod +x $(REDBEAN)
	shasum -c redbean.sums

test-$(REDBEAN): $(REDBEAN) srv-test/.dir
	rm -f $@
	cp "$(REDBEAN)" "$@"
	cd srv-test && zip "../$@" * .init.lua .lua/*
