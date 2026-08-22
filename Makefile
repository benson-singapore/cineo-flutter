SHELL := /bin/bash

APP_VERSION := $(shell perl -ne 'if (/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$$/) { print "$$1\n" }' pubspec.yaml)
BUILD_NUMBER := $(shell perl -ne 'if (/^version: ([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$$/) { print "$$2\n" }' pubspec.yaml)
BRANCH ?= main
WORKFLOW ?= cineo-build.yml

.PHONY: help version bump-patch bump-minor bump-major signing-setup android ios build dispatch release sync-build clean

help:
	@printf '%s\n' \
		'make version VERSION=1.2.0[+BUILD]  修改应用版本' \
		'make bump-patch                  自动递增 patch 版本' \
		'make bump-minor                  自动递增 minor 版本' \
		'make bump-major                  自动递增 major 版本' \
		'make signing-setup               生成并复用本地 Android 自签名 keystore' \
		'make android                     本地构建已签名 Android APK' \
		'make ios                        本地构建未签名 iOS IPA' \
		'make build                       本地构建 APK 和未签名 IPA' \
		'make dispatch GH_TOKEN=...       触发 GitHub Actions' \
		'make release VERSION=...         修改版本、提交、推送并触发 Actions' \
		'make sync-build                  拉取最新 main、递增版本、推送并触发 Actions'

version:
	@test -n "$(VERSION)" || (echo '用法: make version VERSION=1.2.0 或 VERSION=1.2.0+12'; exit 2)
	@./scripts/update_version.sh --version "$(VERSION)"

bump-patch:
	@./scripts/update_version.sh --bump patch

bump-minor:
	@./scripts/update_version.sh --bump minor

bump-major:
	@./scripts/update_version.sh --bump major

signing-setup:
	@./scripts/create_android_signing.sh

android: signing-setup
	@flutter pub get
	@flutter build apk --release

ios:
	@flutter pub get
	@flutter build ios --release --no-codesign
	@rm -rf build/ios/unsigned-ipa/Payload build/ios/unsigned-ipa/Cineo.ipa
	@mkdir -p build/ios/unsigned-ipa/Payload
	@cp -R build/ios/iphoneos/Runner.app build/ios/unsigned-ipa/Payload/Runner.app
	@cd build/ios/unsigned-ipa && zip -qry Cineo.ipa Payload
	@echo "Created unsigned iOS IPA: build/ios/unsigned-ipa/Cineo.ipa"

build: android ios

dispatch:
	@VERSION="$(APP_VERSION)" BUILD_NUMBER="$(BUILD_NUMBER)" WORKFLOW="$(WORKFLOW)" REF="$(BRANCH)" ./scripts/dispatch_workflow.sh

release:
	@if [[ -n "$$(git status --porcelain)" ]]; then echo 'error: working tree is not clean; commit your code changes first.' >&2; exit 1; fi
	@if [[ -n "$(VERSION)" ]]; then \
		if [[ "$(VERSION)" == *+* ]]; then $(MAKE) version VERSION="$(VERSION)"; \
		else ./scripts/update_version.sh --version "$(VERSION)" --build-number "$$(($(BUILD_NUMBER) + 1))"; fi; \
	else $(MAKE) bump-patch; fi
	@git add pubspec.yaml
	@git commit -m "chore: bump app version to $$(perl -ne 'if (/^version: (.*)$$/) { print "$$1\n" }' pubspec.yaml)"
	@git push origin "$(BRANCH)"
	@$(MAKE) dispatch BRANCH="$(BRANCH)"

sync-build:
	@if [[ -n "$$(git status --porcelain)" ]]; then echo 'error: working tree is not clean; commit your code changes first.' >&2; exit 1; fi
	@git fetch origin "$(BRANCH)"
	@git checkout "$(BRANCH)"
	@git pull --rebase origin "$(BRANCH)"
	@$(MAKE) bump-patch
	@git add pubspec.yaml
	@git commit -m "chore: bump app version to $$(perl -ne 'if (/^version: (.*)$$/) { print "$$1\n" }' pubspec.yaml)"
	@git push origin "$(BRANCH)"
	@$(MAKE) dispatch BRANCH="$(BRANCH)"

clean:
	@flutter clean
