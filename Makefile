SHELL := /bin/zsh

APP := pare-cli
APP_BUNDLE := .build/debug/PareApp.app
PROFILE ?= baseline
TOP ?= 20
ARGS ?=

.PHONY: help build test run start run-app run-baseline run-developer run-designer run-video-builder clean

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
	@printf "  make clean                Remove .build artifacts\n"
	@printf "\nExamples:\n"
	@printf "  make start\n"
	@printf "  make run PROFILE=developer TOP=50\n"
	@printf "  make run PROFILE=video-builder TOP=30\n"

build:
	swift build

test:
	swift test

start: run-baseline

run-app: build
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	cp .build/debug/PareApp $(APP_BUNDLE)/Contents/MacOS/PareApp
	cp scripts/AppInfo.plist $(APP_BUNDLE)/Contents/Info.plist
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

clean:
	rm -rf .build
