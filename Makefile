# SwiftPM needs a full Xcode for macOS GUI targets; plain swiftc works with Command Line Tools alone.
SRC := $(shell find Sources/YourTurn -name '*.swift')
BIN := .build/your-turn
APP := .build/YourTurn.app
APPBIN := $(APP)/Contents/MacOS/your-turn

$(BIN): $(SRC)
	@mkdir -p .build
	swiftc -O -framework AppKit -framework SwiftUI $(SRC) -o $@

.build/AppIcon.icns: $(BIN)
	$(BIN) --icon .build/AppIcon.iconset
	iconutil -c icns .build/AppIcon.iconset -o $@

$(APPBIN): $(BIN) Resources/Info.plist .build/AppIcon.icns
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp $(BIN) $(APPBIN)
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	cp .build/AppIcon.icns $(APP)/Contents/Resources/AppIcon.icns
	@touch $(APP)

.PHONY: build app test demo install clean
build: $(BIN)

app: $(APPBIN)

test: $(BIN)
	$(BIN) --test

demo: $(APPBIN)
	$(APPBIN) --demo

install: $(APPBIN)
	-claude mcp remove --scope user redpen >/dev/null 2>&1
	-claude mcp remove --scope user yourturn >/dev/null 2>&1
	-claude mcp remove --scope user your-turn >/dev/null 2>&1
	claude mcp add --scope user your-turn -- $(CURDIR)/$(APPBIN) --mcp

clean:
	rm -rf .build
