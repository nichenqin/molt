.PHONY: build test app install uninstall icon lint format clean smoke release

VERSION ?= 0.1.0

build:
	swift build -c release --product molt
	swift build -c release --product MoltApp

test:
	swift test

app:
	VERSION=$(VERSION) Scripts/package.sh

icon:
	Scripts/make-icon.sh

install: app
	mkdir -p "$(HOME)/Applications" "$(HOME)/.local/bin"
	rm -rf "$(HOME)/Applications/Molt.app"
	ditto "dist/Molt.app" "$(HOME)/Applications/Molt.app"
	cp "dist/molt" "$(HOME)/.local/bin/molt"
	@echo "Installed Molt.app and ~/.local/bin/molt"

uninstall:
	rm -rf "$(HOME)/Applications/Molt.app" "/Applications/Molt.app"
	rm -f "$(HOME)/.local/bin/molt"
	@echo "Removed Molt.app and ~/.local/bin/molt"

lint:
	swift-format lint --recursive Sources Tests || true

format:
	swift-format format --in-place --recursive Sources Tests

smoke:
	swift run -c release molt list --json > /tmp/molt-smoke.json
	python3 -c 'import json; d=json.load(open("/tmp/molt-smoke.json")); print(len(d["items"]), "updates"); assert "reports" in d'

clean:
	swift package clean
	rm -rf dist Resources/build

release: test app
	@echo "Artifacts in dist/ — tag and upload Molt-macos.zip + molt-cli"
