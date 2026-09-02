import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
import '../services/avatar_color.dart';
import '../services/timezone_catalog.dart';
import '../services/secret_redaction.dart';
import 'accent_color_picker.dart';
import 'profile_card.dart';
import 'profile_image_cropper.dart';
import 'timezone_picker_dialog.dart';

Future<bool> showProfileEditor(
  BuildContext context,
  ChatBackend backend,
  UserProfileSummary profile,
) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) =>
          _ProfileEditorDialog(backend: backend, initialProfile: profile),
    ) ??
    false;

Future<bool> showSpaceProfileEditor(
  BuildContext context,
  ChatBackend backend,
  UserProfileSummary globalProfile,
  SpaceProfileOverride? override,
  String spaceId,
) async =>
    await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => _ProfileEditorDialog(
        backend: backend,
        initialProfile: globalProfile,
        spaceId: spaceId,
        spaceOverride: override,
      ),
    ) ??
    false;

class _ProfileEditorDialog extends StatefulWidget {
  const _ProfileEditorDialog({
    required this.backend,
    required this.initialProfile,
    this.spaceId,
    this.spaceOverride,
  });

  final ChatBackend backend;
  final UserProfileSummary initialProfile;
  final String? spaceId;
  final SpaceProfileOverride? spaceOverride;

  @override
  State<_ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<_ProfileEditorDialog> {
  late final _displayName = TextEditingController(
    text: widget.spaceOverride?.nickname ?? widget.initialProfile.displayName,
  );
  late final _pronouns = TextEditingController(
    text: widget.spaceOverride?.pronouns ?? widget.initialProfile.pronouns,
  );
  late final _bio = TextEditingController(
    text: widget.spaceOverride?.bio ?? widget.initialProfile.bio,
  );
  late final _status = TextEditingController(
    text:
        widget.spaceOverride?.statusMessage ??
        widget.initialProfile.statusMessage,
  );
  late int _profileColor =
      widget.spaceOverride?.accentColor ??
      widget.initialProfile.profileColor ??
      0xff6975d9;
  late int _profileColorSecondary =
      widget.spaceOverride?.accentColorSecondary ??
      widget.initialProfile.profileColorSecondary ??
      0xff343966;
  late int _voiceColor =
      widget.spaceOverride?.voiceColor ??
      widget.initialProfile.voiceColor ??
      widget.initialProfile.profileColor ??
      0xff353846;
  String? _timezone;
  Uint8List? _avatar;
  Uint8List? _banner;
  Uint8List? _voiceBackground;
  String _avatarName = 'profile-avatar.png';
  String _avatarMime = 'image/png';
  bool _removeAvatar = false;
  bool _removeBanner = false;
  bool _bannerChanged = false;
  bool _voiceBackgroundChanged = false;
  bool _removeVoiceBackground = false;
  bool _voiceColorChanged = false;
  bool _removeVoiceColor = false;
  late bool _inheritAvatar = widget.spaceOverride?.avatarBytes == null;
  late bool _inheritBanner = widget.spaceOverride?.bannerBytes == null;
  late bool _inheritProfileColor = widget.spaceOverride?.accentColor == null;
  late bool _inheritProfileColorSecondary =
      widget.spaceOverride?.accentColorSecondary == null;
  late bool _inheritVoiceColor = widget.spaceOverride?.voiceColor == null;
  late bool _inheritVoiceBackground =
      widget.spaceOverride?.voiceBackgroundBytes == null;
  bool _saving = false;
  String? _error;

  bool get _spaceProfile => widget.spaceId != null;

  @override
  void initState() {
    super.initState();
    _timezone =
        widget.spaceOverride?.timezone ?? widget.initialProfile.timezone;
    _avatar =
        widget.spaceOverride?.avatarBytes ?? widget.initialProfile.avatarBytes;
    _banner =
        widget.spaceOverride?.bannerBytes ?? widget.initialProfile.bannerBytes;
    _voiceBackground =
        widget.spaceOverride?.voiceBackgroundBytes ??
        widget.initialProfile.voiceBackgroundBytes;
    _displayName.addListener(_refreshPreview);
    _pronouns.addListener(_refreshPreview);
    _bio.addListener(_refreshPreview);
    _status.addListener(_refreshPreview);
  }

  void _refreshPreview() => setState(() {});

  void _resetSpaceFields() {
    if (!_spaceProfile) return;
    setState(() {
      _displayName.text = widget.initialProfile.displayName;
      _pronouns.text = widget.initialProfile.pronouns ?? '';
      _bio.text = widget.initialProfile.bio ?? '';
      _status.text = widget.initialProfile.statusMessage ?? '';
      _timezone = widget.initialProfile.timezone;
      _avatar = widget.initialProfile.avatarBytes;
      _banner = widget.initialProfile.bannerBytes;
      _voiceBackground = widget.initialProfile.voiceBackgroundBytes;
      _profileColor = widget.initialProfile.profileColor ?? 0xff6975d9;
      _profileColorSecondary =
          widget.initialProfile.profileColorSecondary ?? 0xff343966;
      _voiceColor =
          widget.initialProfile.voiceColor ??
          widget.initialProfile.profileColor ??
          0xff353846;
      _inheritAvatar = true;
      _inheritBanner = true;
      _inheritProfileColor = true;
      _inheritProfileColorSecondary = true;
      _inheritVoiceColor = true;
      _inheritVoiceBackground = true;
      _removeAvatar = false;
      _removeBanner = false;
      _removeVoiceBackground = false;
    });
  }

  @override
  void dispose() {
    _displayName.dispose();
    _pronouns.dispose();
    _bio.dispose();
    _status.dispose();
    super.dispose();
  }

  UserProfileSummary get _preview => UserProfileSummary(
    userId: widget.initialProfile.userId,
    displayName: _displayName.text.trim().isEmpty
        ? widget.initialProfile.displayName
        : _displayName.text.trim(),
    avatarBytes: _removeAvatar ? null : _avatar,
    bannerBytes: _removeBanner ? null : _banner,
    presence: widget.initialProfile.presence,
    bio: _bio.text,
    pronouns: _pronouns.text,
    timezone: _timezone,
    statusMessage: _status.text,
    profileColor: _profileColor,
    profileColorSecondary: _profileColorSecondary,
    voiceColor: _voiceColor,
    voiceBackgroundBytes: _removeVoiceBackground ? null : _voiceBackground,
    extensibleFieldsSupported: widget.initialProfile.extensibleFieldsSupported,
  );

  Future<void> _pickAvatar() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.single;
    final bytes = file.bytes ?? await result.xFiles.single.readAsBytes();
    if (!mounted) return;
    final cropped = await showProfileImageCropper(
      context,
      bytes: bytes,
      title: 'Crop profile picture',
      aspectRatio: 1,
      maximumWidth: 1024,
      circularPreview: true,
    );
    if (cropped == null || !mounted) return;
    setState(() {
      _avatar = cropped;
      _avatarName = 'profile-avatar.png';
      _avatarMime = 'image/png';
      _removeAvatar = false;
      _inheritAvatar = false;
    });
  }

  Future<void> _pickBanner() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes =
        result.files.single.bytes ?? await result.xFiles.single.readAsBytes();
    if (!mounted) return;
    final cropped = await showProfileImageCropper(
      context,
      bytes: bytes,
      title: 'Crop profile banner',
      aspectRatio: 3,
      maximumWidth: 1920,
    );
    if (cropped == null || !mounted) return;
    setState(() {
      _banner = cropped;
      _removeBanner = false;
      _bannerChanged = true;
      _inheritBanner = false;
    });
  }

  Future<void> _pickVoiceBackground() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes =
        result.files.single.bytes ?? await result.xFiles.single.readAsBytes();
    if (!mounted) return;
    final cropped = await showProfileImageCropper(
      context,
      bytes: bytes,
      title: 'Crop voice background',
      aspectRatio: 16 / 9,
      maximumWidth: 1600,
    );
    if (cropped == null || !mounted) return;
    setState(() {
      _voiceBackground = cropped;
      _voiceBackgroundChanged = true;
      _removeVoiceBackground = false;
      _inheritVoiceBackground = false;
    });
  }

  Future<void> _pickTimezone() async {
    final timezone = await showDialog<String>(
      context: context,
      builder: (context) => TimezonePickerDialog(selected: _timezone),
    );
    if (timezone != null) setState(() => _timezone = timezone);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_spaceProfile) {
        String? overridden(String value, String? general) =>
            value.trim() == (general ?? '').trim() ? null : value.trim();
        await widget.backend.setSpaceProfileOverride(
          SpaceProfileOverride(
            spaceId: widget.spaceId!,
            nickname: overridden(
              _displayName.text,
              widget.initialProfile.displayName,
            ),
            pronouns: overridden(
              _pronouns.text,
              widget.initialProfile.pronouns,
            ),
            bio: overridden(_bio.text, widget.initialProfile.bio),
            statusMessage: overridden(
              _status.text,
              widget.initialProfile.statusMessage,
            ),
            timezone: _timezone == widget.initialProfile.timezone
                ? null
                : _timezone,
            avatarBytes: _inheritAvatar ? null : _avatar,
            bannerBytes: _inheritBanner ? null : _banner,
            accentColor: _inheritProfileColor ? null : _profileColor,
            accentColorSecondary: _inheritProfileColorSecondary
                ? null
                : _profileColorSecondary,
            voiceColor: _inheritVoiceColor ? null : _voiceColor,
            voiceBackgroundBytes: _inheritVoiceBackground
                ? null
                : _voiceBackground,
          ),
        );
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      final name = _displayName.text.trim();
      if (name.isNotEmpty && name != widget.initialProfile.displayName) {
        await widget.backend.setProfileDisplayName(name);
      }
      if (_removeAvatar) {
        await widget.backend.setProfileAvatar(null);
      } else if (!identical(_avatar, widget.initialProfile.avatarBytes) &&
          _avatar != null) {
        await widget.backend.setProfileAvatar(
          _avatar,
          fileName: _avatarName,
          mimeType: _avatarMime,
        );
      }
      final extensible = widget.initialProfile.extensibleFieldsSupported;
      await widget.backend.updateOwnProfileFields(
        bio: extensible ? _bio.text.trim() : null,
        pronouns: extensible ? _pronouns.text.trim() : null,
        timezone: extensible ? _timezone?.trim() ?? '' : null,
        statusMessage: _status.text.trim(),
        profileColor: extensible ? _profileColor : null,
        profileColorSecondary: extensible ? _profileColorSecondary : null,
        bannerBytes: extensible && _bannerChanged && !_removeBanner
            ? _banner
            : null,
        removeBanner: extensible && _removeBanner,
      );
      if (extensible &&
          (_voiceColorChanged ||
              _voiceBackgroundChanged ||
              _removeVoiceBackground)) {
        await widget.backend.updateOwnVoicePresentation(
          color: _voiceColor,
          backgroundBytes: _voiceBackgroundChanged && !_removeVoiceBackground
              ? _voiceBackground
              : null,
          removeBackground: _removeVoiceBackground,
          removeColor: _removeVoiceColor,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (exception) {
      if (mounted) {
        setState(() => _error = safeErrorMessage(exception));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width < 700;
    return Dialog(
      insetPadding: EdgeInsets.all(compact ? 12 : 40),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1180,
          maxHeight: 820,
          minWidth: compact ? screen.width - 24 : 0,
          minHeight: compact ? min(820, screen.height - 24) : 0,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _spaceProfile
                          ? 'Edit server profile — live preview'
                          : 'Edit profile — live preview',
                      maxLines: compact ? 2 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (_spaceProfile)
                    IconButton(
                      tooltip: 'Reset every field to general profile',
                      onPressed: _resetSpaceFields,
                      icon: const Icon(Icons.restart_alt),
                    ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: Navigator.of(context).pop,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Flex(
                direction: compact ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: compact ? 4 : 3,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(22),
                      child: DeltiecordProfileCard(
                        profile: _preview,
                        preview: true,
                      ),
                    ),
                  ),
                  if (compact)
                    const Divider(height: 1)
                  else
                    const VerticalDivider(width: 1),
                  Flexible(
                    flex: compact ? 6 : 2,
                    fit: compact ? FlexFit.tight : FlexFit.loose,
                    child: SizedBox(
                      width: compact ? double.infinity : 380,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _displayName,
                              decoration: InputDecoration(
                                labelText: 'Display name',
                                suffixIcon: _spaceProfile
                                    ? IconButton(
                                        tooltip: 'Use general display name',
                                        onPressed: () => _displayName.text =
                                            widget.initialProfile.displayName,
                                        icon: const Icon(Icons.restart_alt),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _pronouns,
                              enabled: widget
                                  .initialProfile
                                  .extensibleFieldsSupported,
                              decoration: InputDecoration(
                                labelText: 'Pronouns',
                                suffixIcon: _spaceProfile
                                    ? IconButton(
                                        tooltip: 'Use general pronouns',
                                        onPressed: () => _pronouns.text =
                                            widget.initialProfile.pronouns ??
                                            '',
                                        icon: const Icon(Icons.restart_alt),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _bio,
                              enabled: widget
                                  .initialProfile
                                  .extensibleFieldsSupported,
                              maxLines: 5,
                              maxLength: 500,
                              decoration: InputDecoration(
                                labelText: 'About me',
                                alignLabelWithHint: true,
                                suffixIcon: _spaceProfile
                                    ? IconButton(
                                        tooltip: 'Use general About me',
                                        onPressed: () => _bio.text =
                                            widget.initialProfile.bio ?? '',
                                        icon: const Icon(Icons.restart_alt),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: _status,
                              maxLength: 120,
                              decoration: InputDecoration(
                                labelText: 'Status',
                                hintText: 'What are you up to?',
                                suffixIcon: _spaceProfile
                                    ? IconButton(
                                        tooltip: 'Use general status',
                                        onPressed: () => _status.text =
                                            widget
                                                .initialProfile
                                                .statusMessage ??
                                            '',
                                        icon: const Icon(Icons.restart_alt),
                                      )
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text('Profile gradient — top'),
                            const SizedBox(height: 6),
                            AccentColorPickerButton(
                              color: _profileColor,
                              label: 'Choose top colour',
                              onChanged: (color) => setState(() {
                                _profileColor = color;
                                _inheritProfileColor = false;
                              }),
                            ),
                            if (_spaceProfile)
                              TextButton(
                                onPressed: () => setState(() {
                                  _profileColor =
                                      widget.initialProfile.profileColor ??
                                      0xff6975d9;
                                  _inheritProfileColor = true;
                                }),
                                child: const Text('Use general top colour'),
                              ),
                            const SizedBox(height: 10),
                            const Text('Profile gradient — bottom'),
                            const SizedBox(height: 6),
                            AccentColorPickerButton(
                              color: _profileColorSecondary,
                              label: 'Choose bottom colour',
                              onChanged: (color) => setState(() {
                                _profileColorSecondary = color;
                                _inheritProfileColorSecondary = false;
                              }),
                            ),
                            if (_spaceProfile)
                              TextButton(
                                onPressed: () => setState(() {
                                  _profileColorSecondary =
                                      widget
                                          .initialProfile
                                          .profileColorSecondary ??
                                      0xff343966;
                                  _inheritProfileColorSecondary = true;
                                }),
                                child: const Text('Use general bottom colour'),
                              ),
                            const SizedBox(height: 4),
                            OutlinedButton.icon(
                              onPressed:
                                  widget
                                      .initialProfile
                                      .extensibleFieldsSupported
                                  ? _pickTimezone
                                  : null,
                              icon: const Icon(Icons.public),
                              label: Text(
                                _timezone?.trim().isNotEmpty == true
                                    ? TimezoneCatalog.offsetLabel(_timezone)
                                    : 'Choose timezone',
                              ),
                            ),
                            if (_spaceProfile)
                              TextButton(
                                onPressed: () => setState(
                                  () => _timezone =
                                      widget.initialProfile.timezone,
                                ),
                                child: const Text('Use general timezone'),
                              ),
                            const Divider(height: 26),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _pickAvatar,
                                  icon: const Icon(
                                    Icons.account_circle_outlined,
                                  ),
                                  label: const Text('Choose avatar'),
                                ),
                                TextButton(
                                  onPressed: () => setState(() {
                                    _avatar = _spaceProfile
                                        ? widget.initialProfile.avatarBytes
                                        : null;
                                    _removeAvatar = !_spaceProfile;
                                    _inheritAvatar = _spaceProfile;
                                  }),
                                  child: Text(
                                    _spaceProfile
                                        ? 'Use general avatar'
                                        : 'Remove avatar',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed:
                                      widget
                                          .initialProfile
                                          .extensibleFieldsSupported
                                      ? _pickBanner
                                      : null,
                                  icon: const Icon(Icons.image_outlined),
                                  label: const Text('Choose banner'),
                                ),
                                TextButton(
                                  onPressed:
                                      widget
                                          .initialProfile
                                          .extensibleFieldsSupported
                                      ? () => setState(() {
                                          _banner = _spaceProfile
                                              ? widget
                                                    .initialProfile
                                                    .bannerBytes
                                              : null;
                                          _removeBanner = !_spaceProfile;
                                          _bannerChanged = true;
                                          _inheritBanner = _spaceProfile;
                                        })
                                      : null,
                                  child: Text(
                                    _spaceProfile
                                        ? 'Use general banner'
                                        : 'Remove banner',
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 26),
                            Text(
                              'Voice tile',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Uses the average avatar colour by default. You can '
                              'override it with a colour or a separately cropped '
                              'background.',
                            ),
                            const SizedBox(height: 8),
                            AccentColorPickerButton(
                              color: _voiceColor,
                              label: 'Choose voice colour',
                              onChanged: (color) => setState(() {
                                _voiceColor = color;
                                _voiceColorChanged = true;
                                _removeVoiceColor = false;
                                _inheritVoiceColor = false;
                              }),
                            ),
                            if (_spaceProfile)
                              TextButton(
                                onPressed: () => setState(() {
                                  _voiceColor =
                                      widget.initialProfile.voiceColor ??
                                      widget.initialProfile.profileColor ??
                                      0xff353846;
                                  _inheritVoiceColor = true;
                                }),
                                child: const Text('Use general voice colour'),
                              ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed:
                                      widget
                                          .initialProfile
                                          .extensibleFieldsSupported
                                      ? _pickVoiceBackground
                                      : null,
                                  icon: const Icon(Icons.wallpaper_outlined),
                                  label: const Text('Voice background'),
                                ),
                                TextButton(
                                  onPressed:
                                      widget
                                          .initialProfile
                                          .extensibleFieldsSupported
                                      ? () => setState(() {
                                          _voiceBackground = _spaceProfile
                                              ? widget
                                                    .initialProfile
                                                    .voiceBackgroundBytes
                                              : null;
                                          _voiceBackgroundChanged = true;
                                          _removeVoiceBackground =
                                              !_spaceProfile;
                                          _inheritVoiceBackground =
                                              _spaceProfile;
                                          if (_spaceProfile) {
                                            _voiceColor =
                                                widget
                                                    .initialProfile
                                                    .voiceColor ??
                                                widget
                                                    .initialProfile
                                                    .profileColor ??
                                                0xff353846;
                                            _inheritVoiceColor = true;
                                          } else {
                                            _voiceColorChanged = true;
                                            _removeVoiceColor = true;
                                          }
                                        })
                                      : null,
                                  child: Text(
                                    _spaceProfile
                                        ? 'Use general voice tile'
                                        : 'Use avatar colour',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            AspectRatio(
                              aspectRatio: 16 / 9,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child:
                                    !_removeVoiceBackground &&
                                        _voiceBackground != null
                                    ? Image.memory(
                                        _voiceBackground!,
                                        fit: BoxFit.cover,
                                      )
                                    : FutureBuilder<Color>(
                                        future: _removeVoiceColor
                                            ? representativeAvatarColor(_avatar)
                                            : Future.value(Color(_voiceColor)),
                                        builder: (context, snapshot) =>
                                            ColoredBox(
                                              color:
                                                  snapshot.data ??
                                                  const Color(0xff353846),
                                              child: Center(
                                                child: CircleAvatar(
                                                  radius: 34,
                                                  backgroundImage:
                                                      _avatar == null
                                                      ? null
                                                      : MemoryImage(_avatar!),
                                                  child: _avatar == null
                                                      ? const Icon(
                                                          Icons.person,
                                                          size: 34,
                                                        )
                                                      : null,
                                                ),
                                              ),
                                            ),
                                      ),
                              ),
                            ),
                            if (!widget
                                .initialProfile
                                .extensibleFieldsSupported) ...[
                              const SizedBox(height: 12),
                              const Text(
                                'This homeserver does not advertise extensible '
                                'profile fields. Basic name and avatar editing '
                                'remain available.',
                              ),
                            ],
                            if (_error case final error?) ...[
                              const SizedBox(height: 12),
                              Text(
                                error,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _saving ? null : Navigator.of(context).pop,
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _spaceProfile ? 'Save server profile' : 'Save profile',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
