# Mice Branding Implementation Plan

**Goal:** Apply the approved mouse identity, rename the application to Mice, restore the standard selection cursor and prepare repository metadata for the next push.

**Architecture:** Keep document paths, preferences and bundle identifier stable. Export the approved PNG into ICNS at build time; draw a matching resolution-independent monochrome mouse in the menu bar. Name the app bundle and executable Mice.

**Tech Stack:** Swift/AppKit, Bash, PNG/ICNS.

## Constraints

- Work inline in the existing working tree; preserve unrelated edits.
- macOS 15+, arm64 and x86_64, offline app, no new dependencies.
- Do not push or rename the GitHub repository during this task.

## Steps

- [x] Restore native cursor in SceneCanvasView and remove the experimental cursor implementation.
- [x] Replace StatusIcon with a clean running-mouse template; select the hand-printed app icon in Resources/Branding/AppIcon.png.
- [x] Update scripts/GenerateIcon.swift to export the selected PNG and scripts/build.sh and package.sh to produce Mice.app and Mice distribution files.
- [x] Update app/window labels, README, installation guide and changelog. Record desired GitHub name/description and deferred rename in docs/github-publication.md.
- [x] Run full tests once, universal build once, inspect icon renders and bundle metadata, check package scripts, then one focused review.

## Validation

Full scripts/test.sh passed with pasteboard access; universal build passed (arm64 + x86_64); Info.plist and code signature validated; menu icon template/alpha and 1x/2x renders checked; exported ICNS visually inspected. ZIP/DMG generated and DMG integrity verified. One reviewer found the single-file Swift exporter needed -parse-as-library; fixed and verified. No GitHub changes or push performed.
