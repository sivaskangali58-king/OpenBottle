# Third-party references

The Steam CEF compatibility concept and Chromium flags (`--disable-gpu --single-process`) are based on the open-source project **notpop/steam-on-m1-wine** (MIT): https://github.com/notpop/steam-on-m1-wine

OpenBottle ships its **own C implementation** of a Windows shim, compiled locally via mingw-w64 when the user explicitly requests the fix. No prebuilt Steam component or DLL is included.

Steam is a product of Valve. OpenBottle is not endorsed by Valve or CodeWeavers.
