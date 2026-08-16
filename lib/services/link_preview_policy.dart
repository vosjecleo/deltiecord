/// Privacy policy for URL preview networking.
///
/// Metadata is requested through Matrix. The client only downloads preview
/// media that the homeserver has copied into MXC storage; it never falls back
/// to the linked origin from a message.
abstract final class LinkPreviewNetworkPolicy {
  static const allowsDirectFallback = false;

  static bool mayLoadMedia(Uri uri) => uri.isScheme('mxc');
}
