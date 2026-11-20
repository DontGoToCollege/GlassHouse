# GlassHouse

The owner's personal fork of ImageGlass 10.1 (GPLv3), Windows x64 only. `source\CLAUDE.md` is upstream's guide to the code; it still applies.

- **Build:** `.\build.ps1 -Test` while trying changes, `.\build.ps1` for a release (raise `<GhVersion>` in `source\Directory.Build.props` first). It publishes AOT with the project-local SDK in `.dotnet`, adds `__assets\__app` and `.igportable`, runs `tools\smoke.ps1` (opens a picture on a hidden desktop, never on screen), archives `Versions\Archive\GlassHouse-<v>.zip`, and copies over the live `GlassHouse\` folder without purging (the owner's settings live there).
- **Versions:** `GhVersion` is GlassHouse's. `IgVersion` stays the ImageGlass version it's based on; don't change it to ours, since upstream compares it for config/theme compatibility.
- **Release:** commit, push, `gh release create v<v> Versions\Archive\GlassHouse-<v>.zip`.
- **Upstream fixes:** `git fetch upstream`, then merge or cherry-pick from `upstream/develop`. Keep GlassHouse edits small and marked `// GlassHouse:` so merges stay easy; don't rename namespaces or projects.
- **What differs from ImageGlass** (grep `GlassHouse:`): `Core.IsProEnabled` is always true; licence menus, edition chip and Pro star are hidden; `IG_CheckForUpdateAsync` never contacts imageglass.org (no update check, no usage stats) and opens our releases page; `BHelper.AppName` = GlassHouse (settings folder, registry, window titles); `Lang.Get` swaps "ImageGlass" for the app name in every language; single-instance id `GH_APP`; protocol `glasshouse:`; own icon from `source\__assets\glasshouse\make-icon.py`. File associations (`Win32DefaultAppApi`, owner's rule: Explorer must look exactly as Windows would): each ProgId copies Windows' own type name and icon, taken only from a ProgId whose FriendlyTypeName points into the Windows folder (an installed ImageGlass or a browser would otherwise label the type); GlassHouse never writes the classic `.ext` default, never adds itself to `OpenWithProgids` (both flip a type to "Pick an app", and Explorer then prints the raw value, e.g. `giffile`), and never clears the user's UserChoice. It is offered through `Applications\GlassHouse.exe\SupportedTypes` plus Capabilities, and defaults are picked in Windows Default apps or with Settings' "Make GlassHouse the default" button (`Win32UserChoiceApi`: writes UserChoice with Windows' checksum, re-checking it against defaults Windows wrote before every run). `ms-settings:` links open through explorer.exe, since an elevated GlassHouse can't launch them itself. No `_ext_icons` pack ships (in portable mode that folder is the user's custom icons). With an admin token (this PC runs UAC off, so Explorer reads only HKLM classes) everything is mirrored to HKLM. Test association changes from an admin process started via WMI: this shell's registry writes are sandboxed and never reach the real hive.
- **Licence:** GPLv3, not the owner's usual MIT; keep the ImageGlass copyright and never use the ImageGlass name or logo as GlassHouse's own.

## Gotchas
- Registry writes from Claude's own shell are sandboxed (the desktop app is MSIX): they look applied to that shell but never reach the real hive, and HKLM writes fail. Read, write and test associations from an admin process started with `Invoke-CimMethod Win32_Process Create`. To run GlassHouse's startup repair invisibly, start it that way with `Win32_ProcessStartup.WinstationDesktop = "WinSta0\<hidden desktop>"`.
- Check what Explorer will show with `AssocQueryString` (FRIENDLYDOCNAME/FRIENDLYAPPNAME) and `SHAssocEnumHandlers` from that admin process; "Pick an app" state means Explorer prints the raw `.ext` default as the type.
- One-click default (`Win32UserChoiceApi`): to test without touching real types, write a default for a throwaway extension with two competing ProgIds and check AssocQueryString goes from Unknown to it.
- Merging upstream: only README.md and deleted `.github` files conflicted; keep ours (`git checkout --ours README.md`, `git rm` the .github ones).
- `gh` in a fork targets the *parent* repo by default: run `gh repo set-default DontGoToCollege/GlassHouse` in a new clone, or pass `-R DontGoToCollege/GlassHouse`.
- Build with `-p:Platform=x64` or Magick.NET isn't referenced (build.ps1 does this). The .NET 11 SDK lives only in `.dotnet`; AOT needs the VS C++ Build Tools.
- The smoke check runs the app on a hidden Win32 desktop (`tools\smoke.ps1`), so nothing shows on the owner's screen; it can't screenshot there.

## Not done / unchecked
- Settings still shows the auto-update toggle (does nothing).
- `_ext_icons` file-type icons not checked for ImageGlass branding.
- Linux/Mac projects not rebranded (Windows only).
