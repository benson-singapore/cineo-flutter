SHELL := /bin/bash

# 公开版本号；内部构建号单独维护。
VERSION := 1.0.3
BUILD_NUMBER := 4
BRANCH ?= main

.PHONY: help publish version bump-patch bump-minor bump-major signing-setup android ios build release sync-build clean

help:
	@printf '%s\n' \
		'make publish                    发布新版本、打 tag 并触发 GitHub Actions' \
		'make publish REBUILD=1          沿用当前版本迁移 tag 并重新打包' \
		'Makefile 顶部 VERSION/BUILD_NUMBER 维护公开版本和内部构建号' \
		'make bump-patch                  自动递增 patch 版本' \
		'make bump-minor                  自动递增 minor 版本' \
		'make bump-major                  自动递增 major 版本' \
		'make signing-setup               生成并复用本地 Android 自签名 keystore' \
		'make android                     本地构建已签名 Android APK' \
		'make ios                         本地构建未签名 iOS IPA' \
		'make build                       本地构建 APK 和未签名 IPA'

publish:
	@VERSION="$(VERSION)" BUILD_NUMBER="$(BUILD_NUMBER)" REBUILD="$(REBUILD)" BRANCH="$(BRANCH)" ./scripts/publish.sh

version:
	@test -n "$(VERSION)" || (echo '用法: make version VERSION=1.2.0 BUILD_NUMBER=4'; exit 2)
	@./scripts/update_version.sh --version "$(VERSION)" --build-number "$(BUILD_NUMBER)"

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

release:
	@$(MAKE) publish

sync-build:
	@$(MAKE) publish

clean:
	@flutter clean
