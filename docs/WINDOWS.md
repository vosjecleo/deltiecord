# Windows support

Deltiecord uses Flutter's standard Windows desktop runner. CI builds a complete
portable directory and packages it both as a ZIP and a per-user Inno Setup
installer. Extract the entire portable ZIP before running `deltiecord.exe`;
the executable is not standalone.

The installer defaults to `%LOCALAPPDATA%\Programs\Deltiecord`, creates a Start
Menu shortcut, and optionally creates a desktop shortcut. Upgrading or
uninstalling does not delete Matrix sessions or other per-user application data.

## Build locally

Use Flutter 3.44.9 with the Windows desktop workload and Visual Studio's
"Desktop development with C++" workload:

```powershell
flutter pub get
flutter test
flutter build windows --release
```

The complete runnable output is under
`build\windows\x64\runner\Release`. Inno Setup 6 can compile
`packaging\windows\deltiecord.iss`; CI demonstrates the exact invocation.

## Manual Windows validation still required

A successful cross-platform test suite and Windows compile do not validate
native hardware and shell behavior. Before a 1.0 release, test on physical
Windows 10 and 11 x86-64 systems:

- notification display, sound, activation, room selection, and message jump;
- foregrounding and minimum-window behavior;
- secure-storage persistence across upgrades;
- clipboard images, multi-file drag/drop, file picker, and external open/save;
- microphone/camera enumeration, permission failures, and device switching;
- MatrixRTC audio/video, mute/deafen, reconnect, and output selection;
- screen capture selection, cancellation, stop, and monitor removal;
- hardware-accelerated video playback, streaming, seeking, and fullscreen.

Unsupported native integrations must remain non-fatal. Linux-only GTK,
PipeWire, and XDG portal code is not invoked on Windows.
