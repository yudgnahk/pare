SHELL := /bin/zsh

APP := cleanmymac-cli
PROFILE ?= baseline
TOP ?= 20
ARGS ?=

.PHONY: help build test run start run-app run-baseline run-developer clean

help:
	@printf "Targets:\n"
	@printf "  make build                Build CLI app\n"
	@printf "  make test                 Run unit tests\n"
	@printf "  make start                Start app (baseline profile)\n"
	@printf "  make run-app              Launch SwiftUI macOS app\n"
	@printf "  make run PROFILE=...      Run profile (baseline|developer)\n"
	@printf "  make run-baseline         Run baseline scan\n"
	@printf "  make run-developer        Run developer scan\n"
	@printf "  make clean                Remove .build artifacts\n"
	@printf "\nExamples:\n"
	@printf "  make start\n"
	@printf "  make run PROFILE=developer TOP=50\n"

build:
	swift build

test:
	swift test

start: run-baseline

run-app:
	swift run PareApp

run:
	swift run $(APP) --profile $(PROFILE) --top $(TOP) $(ARGS)

run-baseline:
	swift run $(APP) --profile baseline --top $(TOP) $(ARGS)

run-developer:
	swift run $(APP) --profile developer --top $(TOP) $(ARGS)

clean:
	rm -rf .build
