SHELL := /bin/zsh

APP := pare-cli
APP_BUNDLE := .build/debug/PareApp.app
PROFILE ?= baseline
TOP ?= 20
ARGS ?=

.PHONY: help build test run start run-app ensure-icon run-baseline run-developer run-designer run-video-builder icon release clean

help:
	@printf "Targets:\n"
	@printf "  make build                Build CLI app\n"
	@printf "  make test                 Run unit tests\n"
	@printf "  make start                Start app (baseline profile)\n"
	@printf "  make run-app              Launch SwiftUI macOS app\n"
	@printf "  make run PROFILE=...      Run profile (baseline|developer|designer|video-builder)\n"
	@printf "  make run-baseline         Run baseline scan\n"
	@printf "  make run-developer        Run developer scan\n"
	@printf "  make run-designer         Run designer scan\n"
	@printf "  make run-video-builder    Run video-builder scan\n"
	@printf "  make icon                 Generate AppIcon.icns from scripts/icon.svg (macOS 13+ only)\n"
	@printf "  make release              Build signed + notarized DMG (requires env vars — see scripts/release.sh)\n"
	@printf "  make clean                Remove .build artifacts\n"
	@printf "\nExamples:\n"
	@printf "  make start\n"
	@printf "  make run PROFILE=developer TOP=50\n"
	@printf "  make run PROFILE=video-builder TOP=30\n"
	@printf "  CERT_NAME='Developer ID Application: ...' APPLE_ID=you@example.com NOTARY_PASSWORD=xxxx TEAM_ID=ABCD1234EF make release\n"

build:
	swift build

test:
	swift test

start: run-baseline

# Ensure Dock/in-app assets exist (regenerate when SVG is newer).
ensure-icon:
	@if [ ! -f scripts/AppIcon.icns ] || [ ! -f scripts/PareLogo.png ] \
		|| [ scripts/icon.svg -nt scripts/AppIcon.icns ] \
		|| [ scripts/icon.svg -nt scripts/PareLogo.png ]; then \
		bash scripts/generate-icon.sh; \
	fi

run-app: build ensure-icon
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp .build/debug/PareApp $(APP_BUNDLE)/Contents/MacOS/PareApp
	cp scripts/AppInfo.plist $(APP_BUNDLE)/Contents/Info.plist
	cp scripts/AppIcon.icns $(APP_BUNDLE)/Contents/Resources/AppIcon.icns
	cp scripts/PareLogo.png $(APP_BUNDLE)/Contents/Resources/PareLogo.png
	# Copy SPM resource bundles next to the executable (e.g. app-catalog.json).
	@if [ -d .build/debug/Pare_PareCore.bundle ]; then \
		cp -R .build/debug/Pare_PareCore.bundle $(APP_BUNDLE)/Contents/MacOS/; \
	fi
	# Bump modtime so Dock/Finder refresh the icon after rebuilds.
	touch $(APP_BUNDLE)
	open $(APP_BUNDLE)

run:
	swift run $(APP) --profile $(PROFILE) --top $(TOP) $(ARGS)

run-baseline:
	swift run $(APP) --profile baseline --top $(TOP) $(ARGS)

run-developer:
	swift run $(APP) --profile developer --top $(TOP) $(ARGS)

run-designer:
	swift run $(APP) --profile designer --top $(TOP) $(ARGS)

run-video-builder:
	swift run $(APP) --profile video-builder --top $(TOP) $(ARGS)

icon:
	bash scripts/generate-icon.sh

release:
	bash scripts/release.sh

clean:
	rm -rf .build dist
