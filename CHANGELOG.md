# Changelog

## v1.2.0 — 2026-03-13

**New**
- Backup Wizard: redesigned backup flow into 5 steps (Assistant, Mode, Selection, Name, Result) with a horizontal progress stepper
- Assistant metadata in archive list: backup records now show assistant product type and support assistant-based filtering

**Improved**
- Partial backup semantics: workspace is treated as core required content; optional choices are now focused on top-level state directories
- Selection UX: core required directories are clearly separated from optional directories, with improved multi-column layout for long lists
- Real-time estimate visibility: file count and size estimates are shown in wizard flow before backup starts
- Multi-language coverage expanded for all newly added backup wizard and assistant-filter strings across supported locales

**Fixed**
- Archive preview file tree rendering after backup completion now aligns with expected directory structure
- Version mismatch state is now explicitly shown in list view for quick compatibility review

## v1.1.0 — 2026-03-04

**New**
- Delete backup: permanently remove a backup from disk with a confirmation dialog
- Show in Finder: reveal the backup folder in Finder directly from the detail view

**Improved**
- Reorganized toolbar: list-level actions (Refresh, Import, Backup) moved to the sidebar header; archive-level actions (Finder, Export, Restore, Delete) moved to the detail toolbar, keeping the interface clean and contextual
- Shortened all button labels to single words for a less crowded toolbar
- Version compatibility warnings are now fully localized across all 9 supported languages (previously hardcoded in Chinese)
- Removed the redundant sidebar toggle button from the window toolbar

## v1.0 — 2026-02-01

- Initial release
- Manual backup and restore with double-confirmation
- Archive preview: file tree browser and text config preview
- Export as `.tar.gz` or `.zip`
- OpenClaw scheduler config detection and backup
- Multi-language support: English, Simplified Chinese, Traditional Chinese, German, Spanish, Italian, Russian, Japanese, Korean
- Appearance settings: system / light / dark
- Homebrew Cask distribution
