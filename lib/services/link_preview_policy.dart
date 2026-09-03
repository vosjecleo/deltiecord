import '../models/chat_models.dart';

/// Privacy policy for URL preview networking.
///
/// Metadata is requested through Matrix by default. Direct origin fallback is
/// permitted only after an explicit opt-in and is then performed by the
/// separately hardened, address-pinned preview service.
abstract final class LinkPreviewNetworkPolicy {
  static const trustedProviderDomains = <String>{
    'youtube.com',
    'youtu.be',
    'youtube-nocookie.com',
    'ytimg.com',
    'googlevideo.com',
    'vimeo.com',
    'vimeocdn.com',
    'twitch.tv',
    'ttvnw.net',
    'streamable.com',
    'giphy.com',
    'tenor.com',
    'tenor.googleapis.com',
    'imgur.com',
    'reddit.com',
    'redd.it',
    'redditmedia.com',
    'redditstatic.com',
    'bsky.app',
    'bsky.social',
    'tiktok.com',
    'tiktokcdn.com',
    'x.com',
    'twitter.com',
    'twimg.com',
    'fxtwitter.com',
  };

  static bool allowsDirectFallback(DirectLinkPreviewMode mode, Uri uri) =>
      switch (mode) {
        DirectLinkPreviewMode.none => false,
        DirectLinkPreviewMode.trustedProviders => isTrustedProviderUrl(uri),
        DirectLinkPreviewMode.allPublicSites => true,
      };

  static bool isTrustedProviderUrl(Uri uri) {
    if (!uri.isScheme('http') && !uri.isScheme('https')) return false;
    final host = uri.host.toLowerCase();
    return trustedProviderDomains.any(
      (domain) => host == domain || host.endsWith('.$domain'),
    );
  }

  static bool mayLoadMedia(Uri uri) => uri.isScheme('mxc');
}
