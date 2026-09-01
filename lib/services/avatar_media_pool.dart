import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

typedef AvatarMediaLoader = Future<Uint8List?> Function();

final class _AvatarMediaEntry {
  _AvatarMediaEntry(this.bytes, this.dimension);

  final Uint8List bytes;
  final int dimension;
}

/// Shared bounded cache for Matrix avatar thumbnails.
///
/// Room lists, timelines, profiles, member lists, voice, and notifications all
/// refer to the same immutable MXC content. Pooling by MXC URI prevents each UI
/// surface from issuing its own request. A larger cached thumbnail may satisfy
/// a smaller request, while profile-sized requests never upscale a tiny row
/// thumbnail. Disk entries contain only public/profile media bytes and are
/// cleared with the application's media cache or on logout.
final class AvatarMediaPool {
  AvatarMediaPool({
    Directory? directory,
    this.maximumMemoryBytes = 24 * 1024 * 1024,
    this.maximumDiskBytes = 48 * 1024 * 1024,
    this.maximumEntryBytes = 8 * 1024 * 1024,
  }) : _configuredDirectory = directory;

  static const rowDimension = 128;
  static const profileDimension = 512;

  final Directory? _configuredDirectory;
  final int maximumMemoryBytes;
  final int maximumDiskBytes;
  final int maximumEntryBytes;
  final LinkedHashMap<String, _AvatarMediaEntry> _memory = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _requests = {};
  Future<Directory?>? _directoryRequest;
  int _memoryBytes = 0;
  int _generation = 0;

  Uint8List? peek(Uri uri, int minimumDimension) {
    final candidates =
        _memory.entries
            .where(
              (entry) =>
                  entry.key.startsWith('${uri.toString()}|') &&
                  entry.value.dimension >= minimumDimension,
            )
            .toList(growable: false)
          ..sort((a, b) => a.value.dimension.compareTo(b.value.dimension));
    if (candidates.isEmpty) return null;
    final selected = candidates.first;
    _memory.remove(selected.key);
    _memory[selected.key] = selected.value;
    return selected.value.bytes;
  }

  void seed(Uri uri, Uint8List bytes, int dimension) {
    if (!_valid(uri) || bytes.isEmpty || bytes.length > maximumEntryBytes) {
      return;
    }
    _remember(_key(uri, dimension), bytes, dimension);
  }

  Future<Uint8List?> load(
    Uri uri,
    int minimumDimension,
    AvatarMediaLoader loader,
  ) async {
    if (!_valid(uri)) return null;
    final memory = peek(uri, minimumDimension);
    if (memory != null) return memory;

    final requestKey = _key(uri, minimumDimension);
    final pending = _requests[requestKey];
    if (pending != null) return pending;

    final generation = _generation;
    final request = _load(uri, minimumDimension, loader, generation).whenComplete(
      () {
        // Use a block so this callback returns void. Returning Map.remove's
        // value here would return this same Future and deadlock its completion.
        _requests.remove(requestKey);
      },
    );
    _requests[requestKey] = request;
    return request;
  }

  Future<Uint8List?> _load(
    Uri uri,
    int minimumDimension,
    AvatarMediaLoader loader,
    int generation,
  ) async {
    final disk = await _readDisk(uri, minimumDimension);
    if (disk != null && generation == _generation) return disk;
    final bytes = await loader();
    if (bytes == null ||
        bytes.isEmpty ||
        bytes.length > maximumEntryBytes ||
        generation != _generation) {
      return null;
    }
    seed(uri, bytes, minimumDimension);
    Timer.run(() => unawaited(_writeDisk(uri, bytes, minimumDimension)));
    return bytes;
  }

  Future<void> clear({bool disk = true}) async {
    _generation++;
    _memory.clear();
    _requests.clear();
    _memoryBytes = 0;
    if (!disk) return;
    final directory = await _cacheDirectory();
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
    _directoryRequest = null;
  }

  void _remember(String key, Uint8List bytes, int dimension) {
    final old = _memory.remove(key);
    _memoryBytes -= old?.bytes.length ?? 0;
    _memory[key] = _AvatarMediaEntry(bytes, dimension);
    _memoryBytes += bytes.length;
    while (_memoryBytes > maximumMemoryBytes && _memory.isNotEmpty) {
      final oldest = _memory.keys.first;
      _memoryBytes -= _memory.remove(oldest)?.bytes.length ?? 0;
    }
  }

  Future<Uint8List?> _readDisk(Uri uri, int minimumDimension) async {
    final directory = await _cacheDirectory();
    if (directory == null) return null;
    final dimensions = <int>{
      minimumDimension,
      if (minimumDimension <= rowDimension) rowDimension,
      if (minimumDimension <= profileDimension) profileDimension,
    }.where((dimension) => dimension >= minimumDimension).toList()..sort();
    for (final dimension in dimensions) {
      final file = File(p.join(directory.path, _fileName(uri, dimension)));
      try {
        if (!await file.exists()) continue;
        final length = await file.length();
        if (length <= 0 || length > maximumEntryBytes) {
          await file.delete();
          continue;
        }
        final bytes = await file.readAsBytes();
        await file.setLastModified(DateTime.now());
        seed(uri, bytes, dimension);
        return bytes;
      } catch (_) {
        // A corrupt or concurrently evicted cache entry is a normal miss.
      }
    }
    return null;
  }

  Future<void> _writeDisk(Uri uri, Uint8List bytes, int dimension) async {
    final directory = await _cacheDirectory();
    if (directory == null) return;
    try {
      final file = File(p.join(directory.path, _fileName(uri, dimension)));
      await file.writeAsBytes(bytes, flush: true);
      await _trimDisk(directory);
    } catch (_) {
      // Avatars still remain in memory when a platform cache is unavailable.
    }
  }

  Future<Directory?> _cacheDirectory() {
    final existing = _directoryRequest;
    if (existing != null) return existing;
    return _directoryRequest = () async {
      try {
        final root =
            _configuredDirectory ?? await getApplicationCacheDirectory();
        final directory =
            _configuredDirectory ??
            Directory(p.join(root.path, 'deltiecord', 'avatar-media'));
        await directory.create(recursive: true);
        return directory;
      } catch (_) {
        return null;
      }
    }();
  }

  Future<void> _trimDisk(Directory directory) async {
    final files = <File>[];
    var bytes = 0;
    await for (final entity in directory.list()) {
      if (entity is! File) continue;
      files.add(entity);
      bytes += await entity.length();
    }
    if (bytes <= maximumDiskBytes) return;
    files.sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
    for (final file in files) {
      if (bytes <= maximumDiskBytes) break;
      final length = await file.length();
      await file.delete();
      bytes -= length;
    }
  }

  bool _valid(Uri uri) =>
      uri.isScheme('mxc') && uri.host.isNotEmpty && uri.pathSegments.isNotEmpty;

  String _key(Uri uri, int dimension) => '${uri.toString()}|$dimension';

  String _fileName(Uri uri, int dimension) =>
      '${_fnv1a32(uri.toString()).toRadixString(16).padLeft(8, '0')}-$dimension.bin';

  int _fnv1a32(String value) {
    var hash = 0x811c9dc5;
    for (final byte in value.codeUnits) {
      hash ^= byte;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }
}
