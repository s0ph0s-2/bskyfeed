REDBEAN := redbean-2.2.com
OUTPUT := bskyfeed.com
FILES := .init.lua \
	.lua/date.lua \
	rss.xsl \
    feed.lua \
    generate.lua \
    index.html

build: $(OUTPUT)

clean:
	rm bskyfeed.com

.PHONY: build clean

$(OUTPUT): $(REDBEAN) $(FILES)
	rm -f $@
	cp "$(REDBEAN)" "$@"
	chmod +x "$@"
	zip "$@" $(FILES)

$(REDBEAN):
	curl -sSL "https://redbean.dev/$(REDBEAN)" -o "$(REDBEAN)"
	shasum -c redbean.sums
