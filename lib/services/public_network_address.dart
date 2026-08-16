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
      (first == 192 && second == 168) ||
      (first == 198 && (second == 18 || second == 19)) ||
      first >= 224);
}
