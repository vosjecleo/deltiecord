/// Privacy policy for URL preview networking.
///
/// Metadata is requested through Matrix by default. Direct origin fallback is
/// permitted only after an explicit opt-in and is then performed by the
/// separately hardened, address-pinned preview service.
abstract final class LinkPreviewNetworkPolicy {
  static bool allowsDirectFallback(bool userOptIn) => userOptIn;

  static bool mayLoadMedia(Uri uri) => uri.isScheme('mxc');
}
