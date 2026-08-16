import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../backend/chat_backend.dart';
import '../models/chat_models.dart';
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
      builder: (context) =>
          _ProfileEditorDialog(backend: backend, initialProfile: profile),
    ) ??
    false;

class _ProfileEditorDialog extends StatefulWidget {
  const _ProfileEditorDialog({
    required this.backend,
    required this.initialProfile,
  });

  final ChatBackend backend;
  final UserProfileSummary initialProfile;

  @override
  State<_ProfileEditorDialog> createState() => _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends State<_ProfileEditorDialog> {
  late final _displayName = TextEditingController(
    text: widget.initialProfile.displayName,
  );
  late final _pronouns = TextEditingController(
    text: widget.initialProfile.pronouns,
  );
  late final _bio = TextEditingController(text: widget.initialProfile.bio);
  late final _status = TextEditingController(
    text: widget.initialProfile.statusMessage,
  );
  late int _profileColor = widget.initialProfile.profileColor ?? 0xff6975d9;
  late int _profileColorSecondary =
      widget.initialProfile.profileColorSecondary ?? 0xff343966;
  String? _timezone;
  Uint8List? _avatar;
  Uint8List? _banner;
  String _avatarName = 'profile-avatar.png';
  String _avatarMime = 'image/png';
  bool _removeAvatar = false;
  bool _removeBanner = false;
  bool _bannerChanged = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _timezone = widget.initialProfile.timezone;
    _avatar = widget.initialProfile.avatarBytes;
    _banner = widget.initialProfile.bannerBytes;
    _displayName.addListener(_refreshPreview);
    _pronouns.addListener(_refreshPreview);
    _bio.addListener(_refreshPreview);
    _status.addListener(_refreshPreview);
  }

  void _refreshPreview() => setState(() {});

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
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 820),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
            child: Row(
              children: [
                Text(
                  'Edit profile — live preview',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: DeltiecordProfileCard(
                      profile: _preview,
                      preview: true,
                    ),
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 380,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _displayName,
                          decoration: const InputDecoration(
                            labelText: 'Display name',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _pronouns,
                          enabled:
                              widget.initialProfile.extensibleFieldsSupported,
                          decoration: const InputDecoration(
                            labelText: 'Pronouns',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _bio,
                          enabled:
                              widget.initialProfile.extensibleFieldsSupported,
                          maxLines: 5,
                          maxLength: 500,
                          decoration: const InputDecoration(
                            labelText: 'About me',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _status,
                          maxLength: 120,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                            hintText: 'What are you up to?',
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('Profile gradient — top'),
                        AccentColorPicker(
                          color: _profileColor,
                          onChanged: (color) =>
                              setState(() => _profileColor = color),
                        ),
                        const SizedBox(height: 10),
                        const Text('Profile gradient — bottom'),
                        AccentColorPicker(
                          color: _profileColorSecondary,
                          onChanged: (color) =>
                              setState(() => _profileColorSecondary = color),
                        ),
                        const SizedBox(height: 4),
                        OutlinedButton.icon(
                          onPressed:
                              widget.initialProfile.extensibleFieldsSupported
                              ? _pickTimezone
                              : null,
                          icon: const Icon(Icons.public),
                          label: Text(
                            _timezone?.trim().isNotEmpty == true
                                ? TimezoneCatalog.offsetLabel(_timezone)
                                : 'Choose timezone',
                          ),
                        ),
                        const Divider(height: 26),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _pickAvatar,
                              icon: const Icon(Icons.account_circle_outlined),
                              label: const Text('Choose avatar'),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                _avatar = null;
                                _removeAvatar = true;
                              }),
                              child: const Text('Remove avatar'),
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
                                      _banner = null;
                                      _removeBanner = true;
                                      _bannerChanged = true;
                                    })
                                  : null,
                              child: const Text('Remove banner'),
                            ),
                          ],
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
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : Navigator.of(context).pop,
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Save profile'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
