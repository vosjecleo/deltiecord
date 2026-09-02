Deltiecord v0.9.25 build 77 stable release bundle
====================================================

Linux AppImage:
  chmod +x deltiecord-0.9.25+77-linux-appimage-x86_64.AppImage
  ./deltiecord-0.9.25+77-linux-appimage-x86_64.AppImage

Debian/Ubuntu package:
  sudo apt install ./deltiecord-0.9.25+77-linux-debian-amd64.deb

Verify files:
  sha256sum -c SHA256SUMS

The source archive excludes Git history, build caches, local app data, login
sessions, encryption keys, and generated packaging tools. A desktop Secret
Service is required for secure session/E2EE storage. PipeWire-Pulse or
PulseAudio is required for voice-room audio. Wayland screen sharing also needs
PipeWire, xdg-desktop-portal, and a portal backend for the desktop environment.
