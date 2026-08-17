import 'dart:io';

/// Returns whether [address] is suitable for a client-side public web fetch.
///
/// Link previews must not become a path to loopback, local-network, carrier
/// NAT, benchmark, multicast, or otherwise non-public destinations.
bool isPublicInternetAddress(InternetAddress address) {
  if (address.isLoopback || address.isLinkLocal || address.isMulticast) {
    return false;
  }
  final raw = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    return _isPublicIpv4(raw);
  }
  if (raw.every((byte) => byte == 0)) return false;
  if (raw[0] == 0xfc || raw[0] == 0xfd) return false;
  // Deprecated site-local, discard-only, documentation, and ORCHID ranges are
  // not valid destinations for privacy-sensitive client preview requests.
  if (raw[0] == 0xfe && (raw[1] & 0xc0) == 0xc0) return false; // fec0::/10
  if (raw[0] == 0x01 && raw.skip(1).take(7).every((byte) => byte == 0)) {
    return false; // 100::/64
  }
  if (raw[0] == 0x20 && raw[1] == 0x01 && raw[2] == 0x0d && raw[3] == 0xb8) {
    return false; // 2001:db8::/32
  }
  if (raw[0] == 0x20 &&
      raw[1] == 0x01 &&
      raw[2] == 0 &&
      raw[3] >= 0x10 &&
      raw[3] <= 0x1f) {
    return false; // 2001:10::/28 (ORCHID)
  }
  // IPv4-mapped IPv6 addresses must receive the IPv4 private-range checks.
  final mapped =
      raw.length == 16 &&
      raw.take(10).every((byte) => byte == 0) &&
      raw[10] == 0xff &&
      raw[11] == 0xff;
  return !mapped || _isPublicIpv4(raw.sublist(12));
}

bool _isPublicIpv4(List<int> raw) {
  final first = raw[0];
  final second = raw[1];
  return !(first == 0 ||
      first == 10 ||
      first == 127 ||
      (first == 100 && second >= 64 && second <= 127) ||
      (first == 169 && second == 254) ||
      (first == 172 && second >= 16 && second <= 31) ||
      (first == 192 && second == 0 && raw[2] == 0) ||
      (first == 192 && second == 0 && raw[2] == 2) ||
      (first == 192 && second == 168) ||
      (first == 192 && second == 88 && raw[2] == 99) ||
      (first == 198 && (second == 18 || second == 19)) ||
      (first == 198 && second == 51 && raw[2] == 100) ||
      (first == 203 && second == 0 && raw[2] == 113) ||
      first >= 224);
}
