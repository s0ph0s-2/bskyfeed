VERSION := 0.5
REDBEAN_VERSION := 3.0beta
OUTPUT := bskyfeed.com
SRV_DIR := srv
LIBS := $(ABOUT_FILE) \
	lib/bsky.lua \
	lib/xml.lua \
	lib/rss.lua \
	lib/feed.lua \
	lib/db.lua \
	lib/generate.lua \
	lib/third_party/fullmoon.lua \
	lib/third_party/date.lua \
	lib/jsonfeed.lua
SRCS := src/.init.lua \
	src/rss.xsl \
	src/templates/index.html \
	src/style.css
TEST_LIBS := lib/third_party/luaunit.lua

# Infrastructure variables here
ABOUT_FILE := $(SRV_DIR)/.lua/about.lua
REDBEAN := redbean-$(REDBEAN_VERSION).com
TEST_REDBEAN := test-$(REDBEAN)
SRCS_OUT := $(patsubst src/%,$(SRV_DIR)/%,$(SRCS))
LIBS_OUT := $(patsubst lib/%,$(SRV_DIR)/.lua/%,$(LIBS))
TEST_LIBS_OUT := $(patsubst lib/%,$(SRV_DIR)/.lua/%,$(TEST_LIBS))
CSSO_PATH := $(shell which csso)

build: $(OUTPUT)

clean:
	rm -r $(SRV_DIR) $(TESTS_DIR)
	rm -f $(OUTPUT) $(TEST_REDBEAN)

check: $(TEST_REDBEAN)
	DA_CLIENT_ID=1 DA_CLIENT_SECRET=1 IB_USERNAME=1 IB_PASSWORD=1 ./$< -i test/test.lua

test: check

check-format:
	stylua --check src lib test

format:
	stylua src lib test

.PHONY: build clean check check-format test format

# Don't delete any of these if make is interrupted
.PRECIOUS: $(SRV_DIR)/. $(SRV_DIR)%/.

# Create directories (and their child directories) automatically.
$(SRV_DIR)/.:
	mkdir -p $@

$(SRV_DIR)%/.:
	mkdir -p $@

$(ABOUT_FILE):
	echo "return { NAME = 'werehouse (github.com/s0ph0s-2/werehouse)', VERSION = '$(VERSION)', REDBEAN_VERSION = '$(REDBEAN_VERSION)' }" > "$@"

$(REDBEAN):
	curl -sSL "https://redbean.dev/$(REDBEAN)" -o "$(REDBEAN)" && chmod +x $(REDBEAN)
	shasum -c redbean.sums

# Via https://ismail.badawi.io/blog/automatic-directory-creation-in-make/
# Expand prerequisite lists twice, with automatic variables (like $(@D)) in
# scope the second time.  This sets up the right dependencies for the automatic
# directory creation rules above. (The $$ is so that the first expansion
# replaces $$ with $ and makes the rule syntactically valid the second time.)
.SECONDEXPANSION:

$(SRV_DIR)/.lua/%.lua: lib/%.lua | $$(@D)/.
	cp $< $@

$(SRV_DIR)/%.html: src/%.html | $$(@D)/.
	cp $< $@

$(SRV_DIR)/usr/share/ssl/root/%.pem: src/usr/share/ssl/root/%.pem | $$(@D)/.
	cp $< $@

$(SRV_DIR)/.init.lua: src/.init.lua | $$(@D)/.
	cp $< $@

$(SRV_DIR)/manage.lua: src/manage.lua | $$(@D)/.
	cp $< $@

$(SRV_DIR)/%.css: src/%.css | $$(@D)/.
ifeq (,$(CSSO_PATH))
	cp $< $@
else
	csso $< -o $@
endif

$(SRV_DIR)/%.png: src/%.png | $$(@D)/.
	cp $< $@

$(SRV_DIR)/%.xsl: src/%.xsl | $$(@D)/.
	cp $< $@

$(SRV_DIR)/%.ico: src/%.ico | $$(@D)/.
	cp $< $@

$(SRV_DIR)/%.svg: src/%.svg | $$(@D)/.
	cp $< $@

$(SRV_DIR)/%.webmanifest: src/%.webmanifest | $$(@D)/.
	cp $< $@

$(SRV_DIR)/%.js: src/%.js | $$(@D)/.
	cp $< $@

# Remove SRV_DIR from the start of each path, and also don't try to zip Redbean
# into itself.
$(OUTPUT): $(REDBEAN) $(SRCS_OUT) $(LIBS_OUT) $(ABOUT_FILE)
	if [ ! -f "$@" ]; then cp "$(REDBEAN)" "$@"; fi
	cd srv && zip -R "../$@" $(patsubst $(SRV_DIR)/%,%,$(filter-out $<,$?))

$(TEST_REDBEAN): $(REDBEAN) $(SRCS_OUT) $(LIBS_OUT) $(TEST_LIBS_OUT) $(ABOUT_FILE)
	if [ ! -f "$@" ]; then cp "$(REDBEAN)" "$@"; fi
	cd srv && zip -R "../$@" $(patsubst $(SRV_DIR)/%,%,$(filter-out $<,$?))
