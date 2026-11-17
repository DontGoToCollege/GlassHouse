# GlassHouse

The owner's personal fork of ImageGlass 10.1 (GPLv3), Windows x64 only. `source\CLAUDE.md` is upstream's guide to the code; it still applies.

- **Build:** `.\build.ps1 -Test` while trying changes, `.\build.ps1` for a release (raise `<GhVersion>` in `source\Directory.Build.props` first). It publishes AOT with the project-local SDK in `.dotnet`, adds `__assets\__app` and `.igportable`, runs `tools\smoke.ps1` (opens a picture on a hidden desktop, never on screen), archives `Versions\Archive\GlassHouse-<v>.zip`, and copies over the live `GlassHouse\` folder without purging (the owner's settings live there).
- **Versions:** `GhVersion` is GlassHouse's. `IgVersion` stays the ImageGlass version it's based on; don't change it to ours, since upstream compares it for config/theme compatibility.
- **Release:** commit, push, `gh release create v<v> Versions\Archive\GlassHouse-<v>.zip`.
- **Upstream fixes:** `git fetch upstream`, then merge or cherry-pick from `upstream/develop`. Keep GlassHouse edits small and marked `// GlassHouse:` so merges stay easy; don't rename namespaces or projects.
- **What differs from ImageGlass** (grep `GlassHouse:`): `Core.IsProEnabled` is always true; licence menus, edition chip and Pro star are hidden; `IG_CheckForUpdateAsync` never contacts imageglass.org (no update check, no usage stats) and opens our releases page; `BHelper.AppName` = GlassHouse (settings folder, registry, window titles); `Lang.Get` swaps "ImageGlass" for the app name in every language; single-instance id `GH_APP`; protocol `glasshouse:`; own icon from `source\__assets\glasshouse\make-icon.py`.
- **Licence:** GPLv3, not the owner's usual MIT; keep the ImageGlass copyright and never use the ImageGlass name or logo as GlassHouse's own.
