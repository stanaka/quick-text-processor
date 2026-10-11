# QuickTextProcessor build orchestration.
#
#   make build   - compile (swift build)
#   make app     - assemble build/QuickTextProcessor.app
#   make dmg VERSION=0.1.0 - package an arm64 release disk image
#   make icon    - regenerate build/AppIcon.icns from Support/AppIcon.png
#   make run     - build, assemble and launch the app
#   make test    - run unit tests (QTPCore)
#   make clean   - remove all build products
#   make cert    - one-time: create a stable dev code-signing identity
#
# Signing: `make cert` once creates a self-signed "QuickTextProcessor Dev"
# certificate; `make app` then finds and uses it automatically so macOS keeps
# the Accessibility grant across rebuilds. Without it, `make app` falls back
# to any "Apple Development" identity, then to ad-hoc ("-", grant is dropped
# on every rebuild). Override explicitly with `make IDENTITY=... app`.

APP      := QuickTextProcessor
CONFIG   ?= release
ARCH     ?=
VERSION  ?=
SWIFT_BUILD_FLAGS = -c $(CONFIG) $(if $(ARCH),--arch $(ARCH))
BINDIR   = $(shell swift build $(SWIFT_BUILD_FLAGS) --show-bin-path)
BUNDLE   := build/$(APP).app
CONTENTS := $(BUNDLE)/Contents
ICON_SRC := Support/AppIcon.png
ICON_OUT := build/AppIcon.icns
# Empty means "auto-detect in the app recipe"; set IDENTITY=- to force ad-hoc.
IDENTITY ?=
DEV_CERT := QuickTextProcessor Dev

.PHONY: build app icon run test clean cert dmg

build:
	swift build $(SWIFT_BUILD_FLAGS)

# Regenerated only when the master artwork or the generator changes.
$(ICON_OUT): $(ICON_SRC) scripts/make-icon.swift
	@mkdir -p build
	swift scripts/make-icon.swift "$(ICON_SRC)" "$@"

icon: $(ICON_OUT)

app: build $(if $(wildcard $(ICON_SRC)),$(ICON_OUT))
	rm -rf "$(BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp Support/Info.plist "$(CONTENTS)/Info.plist"
	@if [ -n "$(VERSION)" ]; then \
		bash scripts/validate-version.sh "$(VERSION)" && \
		/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(CONTENTS)/Info.plist" && \
		/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" "$(CONTENTS)/Info.plist"; \
	fi
	printf 'APPL????' > "$(CONTENTS)/PkgInfo"
	cp "$(BINDIR)/$(APP)" "$(CONTENTS)/MacOS/$(APP)"
	@# SwiftPM puts target resources into *.bundle next to the binary;
	@# Bundle.module finds them via Bundle.main.resourceURL inside the .app.
	@for b in "$(BINDIR)"/*.bundle; do \
		if [ -e "$$b" ]; then cp -R "$$b" "$(CONTENTS)/Resources/"; fi; \
	done
	@# Dock/Finder read the icon from Contents/Resources via CFBundleIconFile.
	@if [ -e "$(ICON_OUT)" ]; then \
		cp "$(ICON_OUT)" "$(CONTENTS)/Resources/AppIcon.icns"; \
	else \
		echo "warning: no app icon ($(ICON_SRC) missing); building without one."; \
	fi
	@# Prefer a stable identity (see `make cert`); ad-hoc signatures change on
	@# every build and make macOS drop the Accessibility grant. Sign by cert
	@# hash so duplicate certificate names never make codesign ambiguous.
	@identity='$(IDENTITY)'; \
	if [ -z "$$identity" ] && command -v security >/dev/null 2>&1; then \
		ids=$$(security find-identity -v -p codesigning 2>/dev/null || true); \
		hash=$$(printf '%s\n' "$$ids" \
			| sed -n 's/^[^)]*) \([0-9A-F]\{40\}\) "$(DEV_CERT)".*/\1/p' | head -n 1); \
		if [ -z "$$hash" ]; then \
			hash=$$(printf '%s\n' "$$ids" \
				| sed -n 's/^[^)]*) \([0-9A-F]\{40\}\) "Apple Development.*/\1/p' | head -n 1); \
		fi; \
		identity=$$hash; \
	fi; \
	if [ -z "$$identity" ]; then \
		identity='-'; \
		echo "warning: signing ad-hoc; macOS will forget the Accessibility grant on rebuild. Run 'make cert' once to fix this."; \
	fi; \
	echo "codesign identity: $$identity"; \
	codesign --force --deep --timestamp=none --sign "$$identity" "$(BUNDLE)"
	@echo "Assembled $(BUNDLE)"

run: app
	@pkill -x $(APP) >/dev/null 2>&1 || true
	open "$(BUNDLE)"

dmg:
	bash scripts/validate-version.sh "$(VERSION)"
	$(MAKE) app CONFIG=release ARCH=arm64 VERSION="$(VERSION)" IDENTITY=-
	bash scripts/package-dmg.sh "$(BUNDLE)" "$(VERSION)"
	bash scripts/verify-dmg.sh "build/$(APP)-$(VERSION)-arm64.dmg" "$(VERSION)"

test:
	swift test

clean:
	swift package clean
	rm -rf build

cert:
	./scripts/dev-cert.sh
