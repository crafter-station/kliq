.DEFAULT_GOAL := help

.PHONY: help build run dmg release web-sounds icon og dmg-background diagnose clean

help:
	@echo "make build                    build build/Kliq.app (CONFIG=debug for a debug build)"
	@echo "make run                      build and open Kliq.app"
	@echo "make dmg                      build and open an unnotarized DMG to preview the installer"
	@echo "make release VERSION=0.0.3    build a notarized, stapled DMG"
	@echo "make web-sounds               rebuild site/sounds from Resources/Sounds"
	@echo "make icon                     re-render AppIcon.icns + site/icon.png from AppIcon.svg"
	@echo "make og                       re-render site/og.png link preview"
	@echo "make dmg-background           re-render Resources/DMGBackground.tiff from Tools/dmg.html"
	@echo "make diagnose                 print what the sleep triggers currently detect"
	@echo "make clean                    remove build/ and .build/"

build:
	./build.sh

run: build
	open build/Kliq.app

dmg: build
	Tools/make_dmg.sh build/Kliq.app build/Kliq.dmg
	open build/Kliq.dmg

release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=0.0.3" >&2; exit 1; }
	./release.sh $(VERSION)

web-sounds:
	python3 Tools/make_web_sounds.py

icon:
	Tools/render_icon.sh

og:
	Tools/render_og.sh

dmg-background:
	Tools/render_dmg_background.sh

diagnose:
	swift Tools/diagnose_triggers.swift

clean:
	rm -rf build .build
