VERSION := 0.5
REDBEAN_VERSION := 2.2
REDBEAN := redbean-$(REDBEAN_VERSION).com
OUTPUT := bskyfeed.com
ABOUT_FILE := .lua/about.lua
FILES := .init.lua \
	.lua/date.lua \
	.lua/xml.lua \
	.lua/bsky.lua \
	$(ABOUT_FILE) \
	rss.xsl \
    feed.lua \
	generate.lua \
	style.css \
    index.html

build: $(OUTPUT)

clean:
	rm $(OUTPUT) $(ABOUT_FILE)

.PHONY: build clean

$(ABOUT_FILE):
	echo "return { NAME = '$(OUTPUT)', VERSION = '$(VERSION)', REDBEAN_VERSION = '$(REDBEAN_VERSION)' }" > "$@"

$(OUTPUT): $(REDBEAN) $(FILES)
	rm -f $@
	cp "$(REDBEAN)" "$@"
	chmod +x "$@"
	zip "$@" $(FILES)

$(REDBEAN):
	curl -sSL "https://redbean.dev/$(REDBEAN)" -o "$(REDBEAN)"
	shasum -c redbean.sums
