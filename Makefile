PREFIX ?= /usr/local
BINARY = RescreenBroker
BUILD_DIR = .build/release

.PHONY: build install uninstall clean test

build:
	swift build -c release

test:
	swift test

install: build
	install -d $(PREFIX)/bin
	install $(BUILD_DIR)/$(BINARY) $(PREFIX)/bin/rescreen

uninstall:
	rm -f $(PREFIX)/bin/rescreen

clean:
	swift package clean
