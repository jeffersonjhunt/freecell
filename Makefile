# Solitaire — build, run, test and profile on the Mac from the command line, no Xcode IDE.
# Run `make help` for targets. Needs full Xcode as the active toolchain:
#   sudo xcode-select -s /Applications/Xcode.app
# The .xcodeproj is generated from project.yml by the XcodeGen pinned in .xcodegen-version
# (tools/xcodegen builds it once into a shared cache).

# The version testers and the store see: project.yml's MARKETING_VERSION.
VERSION := $(shell sed -n 's/^ *MARKETING_VERSION: *"\(.*\)"/\1/p' project.yml)

.DEFAULT_GOAL := build

PROJECT   := Solitaire.xcodeproj
SCHEME    := Solitaire
CONFIG    := Debug
DERIVED   := build/DerivedData
MAC_APP   := $(DERIVED)/Build/Products/$(CONFIG)/Solitaire.app
IOS_APP   := $(DERIVED)/Build/Products/$(CONFIG)-iphoneos/Solitaire.app
XCODEGEN  := tools/xcodegen
MAC_PID   := pgrep -n -f "$(CURDIR)/$(MAC_APP)/Contents/MacOS/Solitaire"
XCB       := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -derivedDataPath $(DERIVED)

# Signing — per developer, so read from gitignored files (or set on the command line):
#   1. SIGN_ID  (.signid)  — a named code-signing identity; manual signing. Mac only.
#   2. DEV_TEAM (.devteam) — your 10-character Apple team ID; automatic signing with your Apple
#                            Development certificate. Required for an iPhone or iPad.
#   3. (neither)           — ad-hoc (`-`): fine for your own Mac, not for a device.
SIGN_ID  ?= $(shell cat .signid 2>/dev/null)
DEV_TEAM ?= $(shell cat .devteam 2>/dev/null)

# Signing without a GUI session (e.g. over SSH on a build Mac). SSH cannot use the login keychain's
# keys or the Apple ID signed in to Xcode, so when this per-machine file exists, builds unlock a
# dedicated signing keychain and provision with an App Store Connect API key instead. It holds
# make-syntax lines: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH, SIGNING_KEYCHAIN and
# SIGNING_KEYCHAIN_PASS_FILE (a file holding the keychain's password). Without it, builds sign as
# before: login keychain and the Xcode account, which works at the Mac itself.
ASC_ENV ?= $(HOME)/.config/appstoreconnect/api.env
-include $(ASC_ENV)
ifneq ($(strip $(ASC_KEY_ID)),)
  ASC_AUTH := -authenticationKeyPath "$(ASC_KEY_PATH)" -authenticationKeyID $(ASC_KEY_ID) \
              -authenticationKeyIssuerID $(ASC_ISSUER_ID)
endif
ifneq ($(strip $(SIGNING_KEYCHAIN)),)
  # The password is read by the shell at run time, so make never prints it.
  UNLOCK := security unlock-keychain -p "$$(cat "$(SIGNING_KEYCHAIN_PASS_FILE)")" "$(SIGNING_KEYCHAIN)" &&
  KEYCHAIN_FLAG := OTHER_CODE_SIGN_FLAGS="--keychain $(SIGNING_KEYCHAIN)"
endif

ifneq ($(strip $(SIGN_ID)),)
  MAC_SIGN := CODE_SIGN_IDENTITY="$(SIGN_ID)" CODE_SIGN_STYLE=Manual
else ifneq ($(strip $(DEV_TEAM)),)
  MAC_SIGN := CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(DEV_TEAM) $(KEYCHAIN_FLAG) \
              -allowProvisioningUpdates $(ASC_AUTH)
else
  MAC_SIGN := CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual
endif
IOS_SIGN := CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(DEV_TEAM) $(KEYCHAIN_FLAG) \
            -allowProvisioningUpdates -allowProvisioningDeviceRegistration $(ASC_AUTH)

# The iPhone or iPad to install on and profile: its name or UDID, from the gitignored .device file
# or DEVICE=… on the command line (`make devices` lists them).
DEVICE ?= $(shell cat .device 2>/dev/null)

# Profiling opens the Debug-only King→Ace position (UITestScenario.swift) with its own save file
# and settings, so it never touches your game. It profiles the Debug build — slower than Release,
# so a clean trace holds for both.
BUNDLE_ID   := com.oneoffendeavors.solitaire
PROFILE_ENV := SOLITAIRE_SCENARIO=kingToAce SOLITAIRE_SAVE_FILE=profiling SOLITAIRE_DEFAULTS_SUITE=profiling
PROFILE_ENV_JSON := {"SOLITAIRE_SCENARIO":"kingToAce","SOLITAIRE_SAVE_FILE":"profiling","SOLITAIRE_DEFAULTS_SUITE":"profiling"}
TEMPLATE ?= Animation Hitches
TIME     ?= 30s
TRACES   := build/traces
# OPEN=no records and saves the trace without opening Instruments — for unattended runs, which
# would otherwise leave Instruments (and its save prompt on quit) on the Mac's screen.
OPEN     ?= yes

.PHONY: help xcodegen generate build run logs stop test uitest devices device install profile \
        profile-mac archive export upload testflight need-device need-team need-asc clean

help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

xcodegen: ## Build the pinned XcodeGen if needed
	$(XCODEGEN) --version

generate: ## Generate the .xcodeproj from project.yml
	$(XCODEGEN) generate --quiet

build: generate ## Build the Mac app (signed per .signid / .devteam, else ad-hoc)
	$(UNLOCK) $(XCB) -destination 'generic/platform=macOS' $(MAC_SIGN) build
	@echo ">> built: $(MAC_APP)"

run: build ## Build, launch the Mac app, stream its logs (stops when you quit it)
	@open "$(MAC_APP)"
	@echo ">> launched — streaming logs (stops when you quit Solitaire; Ctrl-C also works):"
	@app_pid=""; \
	for i in $$(seq 1 50); do app_pid=$$($(MAC_PID)); [ -n "$$app_pid" ] && break; sleep 0.1; done; \
	log stream --style compact --predicate 'process == "Solitaire"' & \
	log_pid=$$!; \
	trap 'kill $$log_pid 2>/dev/null' INT TERM EXIT; \
	if [ -n "$$app_pid" ]; then \
	  while kill -0 "$$app_pid" 2>/dev/null; do sleep 0.5; done; \
	  kill $$log_pid 2>/dev/null || true; \
	else \
	  wait $$log_pid; \
	fi

logs: ## Stream the running app's logs
	log stream --style compact --predicate 'process == "Solitaire"'

stop: ## Quit the running Mac app
	-killall Solitaire

test: generate ## Engine tests + the app's unit tests on the Mac
	swift test --package-path Packages/SolitaireEngine
	$(UNLOCK) $(XCB) -destination 'platform=macOS' -only-testing:SolitaireTests $(MAC_SIGN) test

uitest: generate ## UI tests on the Mac — leave the Mac alone while they run
	$(UNLOCK) $(XCB) -destination 'platform=macOS' -only-testing:SolitaireUITests $(MAC_SIGN) test

devices: ## List iPhones and iPads (connected devices and simulators)
	xcrun devicectl list devices

device: need-team generate ## Build for any iPhone or iPad (needs .devteam and one registered device)
	$(UNLOCK) $(XCB) -destination 'generic/platform=iOS' $(IOS_SIGN) build
	@echo ">> built: $(IOS_APP)"

# Builds for DEVICE itself, not "any iOS device": that is what lets xcodebuild register it with your
# team, and a development profile cannot exist until the team has a device.
install: need-device need-team generate ## Build for DEVICE (registering it if new) and install it
	$(UNLOCK) $(XCB) -destination "platform=iOS,name=$(DEVICE)" $(IOS_SIGN) build
	xcrun devicectl device install app --device "$(DEVICE)" "$(IOS_APP)"

# Both profile targets launch the app normally, then attach the recording to it. (Launched by
# xctrace itself, the Mac app came up without a window and outlived the recording.)
profile: install ## Record Animation Hitches on DEVICE from the King→Ace position, then open the trace
	@test "$(CONFIG)" = Debug || { echo "profiling needs CONFIG=Debug: the King→Ace position is Debug-only"; exit 1; }
	@mkdir -p $(TRACES)
	xcrun devicectl device process launch --device "$(DEVICE)" --terminate-existing \
	  --environment-variables '$(PROFILE_ENV_JSON)' $(BUNDLE_ID)
	@sleep 2
	@echo ">> recording $(TIME) on $(DEVICE) — drag the King→Ace run back and forth"
	xcrun xctrace record --template "$(TEMPLATE)" --device "$(DEVICE)" --time-limit $(TIME) \
	  --output "$(TRACES)/device-$$(date +%Y%m%d-%H%M%S).trace" --attach Solitaire
	@trace="$$(ls -td $(TRACES)/*.trace | head -1)"; \
	if [ "$(OPEN)" = no ]; then echo ">> saved: $$trace"; else open "$$trace"; fi

profile-mac: build ## The same recording on this Mac (a separate copy; your game is untouched)
	@test "$(CONFIG)" = Debug || { echo "profiling needs CONFIG=Debug: the King→Ace position is Debug-only"; exit 1; }
	@mkdir -p $(TRACES)
	open -n $(addprefix --env ,$(PROFILE_ENV)) "$(MAC_APP)"
	@sleep 2
	@echo ">> recording $(TIME) — drag the King→Ace run back and forth"
	xcrun xctrace record --template "$(TEMPLATE)" --time-limit $(TIME) \
	  --output "$(TRACES)/mac-$$(date +%Y%m%d-%H%M%S).trace" --attach $$($(MAC_PID))
	@trace="$$(ls -td $(TRACES)/*.trace | head -1)"; \
	if [ "$(OPEN)" = no ]; then echo ">> saved: $$trace"; else open "$$trace"; fi

# --- TestFlight --------------------------------------------------------------------------------
# make archive export upload, then make testflight to watch Apple process the builds.
# Every upload needs a higher build number than the last; the UTC time always is.
RELEASE_DIR  := build/release
BUILD_NUMBER ?= $(shell date -u +%Y%m%d%H%M)
RELEASE_XCB  := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release

archive: need-team need-asc generate ## Release archives for iOS and the Mac (build number: UTC time)
	@rm -rf $(RELEASE_DIR) && mkdir -p $(RELEASE_DIR) && echo $(BUILD_NUMBER) > $(RELEASE_DIR)/build-number
	@echo ">> archiving $(VERSION) ($(BUILD_NUMBER))"
	@# Both signed with the team: signing is what embeds the entitlements (Game Center, iCloud's
	@# key-value store, the Mac sandbox) — an unsigned archive exported without them, and the
	@# upload was accepted all the same (U21). The development profile this needs covers the
	@# registered devices; export then re-signs for the App Store.
	$(UNLOCK) $(RELEASE_XCB) -destination 'generic/platform=iOS' -archivePath $(RELEASE_DIR)/Solitaire-ios.xcarchive \
	  CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(DEV_TEAM) $(KEYCHAIN_FLAG) \
	  -allowProvisioningUpdates $(ASC_AUTH) archive
	$(UNLOCK) $(RELEASE_XCB) -destination 'generic/platform=macOS' -archivePath $(RELEASE_DIR)/Solitaire-macos.xcarchive \
	  CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=$(DEV_TEAM) $(KEYCHAIN_FLAG) \
	  -allowProvisioningUpdates $(ASC_AUTH) archive

export: need-team need-asc ## Sign the archives for the App Store (Apple signs, via the API key) and check them
	@test -f $(RELEASE_DIR)/build-number || { echo "Run make archive first."; exit 1; }
	@printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
	  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
	  '<plist version="1.0"><dict>' \
	  '<key>method</key><string>app-store-connect</string><key>destination</key><string>export</string>' \
	  '<key>teamID</key><string>$(DEV_TEAM)</string><key>signingStyle</key><string>automatic</string>' \
	  '<key>manageAppVersionAndBuildNumber</key><false/>' \
	  '</dict></plist>' > $(RELEASE_DIR)/ExportOptions.plist
	@for p in ios macos; do rm -rf $(RELEASE_DIR)/export-$$p; \
	  echo ">> exporting $$p"; \
	  $(UNLOCK) xcodebuild -exportArchive -archivePath $(RELEASE_DIR)/Solitaire-$$p.xcarchive \
	    -exportPath $(RELEASE_DIR)/export-$$p -exportOptionsPlist $(RELEASE_DIR)/ExportOptions.plist \
	    -allowProvisioningUpdates $(ASC_AUTH) > $(RELEASE_DIR)/export-$$p.log 2>&1 \
	  || { tail -20 $(RELEASE_DIR)/export-$$p.log; exit 1; }; done
	TEAM=$(DEV_TEAM) tools/check-release.sh $(RELEASE_DIR)

upload: need-asc ## Upload exactly the checked packages to App Store Connect (TestFlight)
	@test -f $(RELEASE_DIR)/export-ios/Solitaire.ipa -a -f $(RELEASE_DIR)/export-macos/Solitaire.pkg \
	  || { echo "Run make archive export first."; exit 1; }
	TEAM=$(DEV_TEAM) tools/check-release.sh $(RELEASE_DIR)
	@for f in $(RELEASE_DIR)/export-ios/Solitaire.ipa $(RELEASE_DIR)/export-macos/Solitaire.pkg; do \
	  echo ">> uploading $$f"; \
	  xcrun altool --upload-package "$$f" --api-key $(ASC_KEY_ID) --api-issuer $(ASC_ISSUER_ID) \
	    --p8-file-path "$(ASC_KEY_PATH)" || exit 1; done
	@echo ">> uploaded $(VERSION) ($$(cat $(RELEASE_DIR)/build-number)); Apple processes it for a few minutes — make testflight"

testflight: need-asc ## Show recent uploads and whether Apple has finished processing them
	ASC_ENV="$(ASC_ENV)" tools/asc.py builds

need-asc:
	@test -n "$(strip $(ASC_KEY_ID))" || { echo "Needs App Store Connect API settings in $(ASC_ENV) — see README › Signing."; exit 1; }
need-team:
	@test -n "$(strip $(DEV_TEAM))" || { echo "A device build needs your Apple team ID: echo XXXXXXXXXX > .devteam"; exit 1; }

need-device:
	@test -n "$(DEVICE)" || { echo "Which device? echo '<name or UDID>' > .device, or DEVICE=… (see make devices)"; exit 1; }

clean: ## Remove build output and the generated project
	rm -rf build $(PROJECT)
