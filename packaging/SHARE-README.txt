Deltiecord v0.9.19 beta test bundle
================================

Linux AppImage:
  chmod +x Deltiecord-0.9.19-x86_64.AppImage
  ./Deltiecord-0.9.19-x86_64.AppImage

Debian/Ubuntu package:
  sudo apt install ./deltiecord_0.9.19_amd64.deb

Verify files:
  sha256sum -c SHA256SUMS

The source archive excludes Git history, build caches, local app data, login
sessions, encryption keys, and generated packaging tools. A desktop Secret
Service is required for secure session/E2EE storage. PipeWire-Pulse or
PulseAudio is required for voice-room audio. Wayland screen sharing also needs
PipeWire, xdg-desktop-portal, and a portal backend for the desktop environment.
