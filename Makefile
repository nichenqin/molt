.PHONY: build test app install uninstall icon lint format clean smoke release

VERSION ?= 0.1.0

build:
	swift build -c release --product remige
	swift build -c release --product RemigeApp

test:
	swift test

app:
	VERSION=$(VERSION) Scripts/package.sh

icon:
	Scripts/make-icon.sh

install: app
	mkdir -p "$(HOME)/Applications" "$(HOME)/.local/bin"
	rm -rf "$(HOME)/Applications/Remige.app"
	ditto "dist/Remige.app" "$(HOME)/Applications/Remige.app"
	cp "dist/remige" "$(HOME)/.local/bin/remige"
	@echo "Installed Remige.app and ~/.local/bin/remige"

uninstall:
	rm -rf "$(HOME)/Applications/Remige.app" "/Applications/Remige.app"
	rm -f "$(HOME)/.local/bin/remige"
	@echo "Removed Remige.app and ~/.local/bin/remige"

lint:
	xcrun swift-format lint --recursive Sources Tests

format:
	xcrun swift-format format --in-place --recursive Sources Tests

smoke:
	swift run -c release remige list --json > /tmp/remige-smoke.json
	python3 -c 'import json; d=json.load(open("/tmp/remige-smoke.json")); print(len(d["items"]), "updates"); assert "reports" in d'

clean:
	swift package clean
	rm -rf dist Resources/build

release: test app
	@echo "Artifacts in dist/ — tag and upload Remige-macos.zip + remige-cli"
