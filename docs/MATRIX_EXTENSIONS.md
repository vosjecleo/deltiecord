# Deltiecord Matrix extensions

Deltiecord uses normal Matrix rooms, Spaces, events, encryption, media, and
MatrixRTC. The fields below add presentation metadata only. Other clients can
safely ignore every `net.deltiecord.*` value.

## Room presentation

- Type: room state event
- Event type: `net.deltiecord.room.presentation`
- State key: empty string

```json
{ "kind": "text" }
```

`kind` is `text` or `voice`. Missing, unknown, or ignored state is presented as
a normal text room. A voice room remains an interoperable Matrix room and uses
standard MatrixRTC state for participation.

## Space channel categories and order

- Type: Space room state event
- Event type: `net.deltiecord.space.channels`
- State key: empty string

```json
{
  "version": 1,
  "categories": [
    { "id": "category-123", "name": "Games" },
    { "id": "category-456", "name": "Voice" }
  ],
  "rooms": {
    "!text:example.org": "category-123",
    "!voice:example.org": "category-456"
  }
}
```

Category array order is display order. `rooms` maps child room IDs to category
IDs; absent rooms are uncategorized. Actual room membership remains standard
`m.space.child` state. Deltiecord writes the standard `order` property on
`m.space.child` for room ordering, so clients that understand Matrix Space
ordering can retain a useful order without understanding categories.

Collapsed categories are a per-account UI preference in
`net.deltiecord.settings`, not public room state.

## Synced Deltiecord settings

- Type: global user account data
- Event type: `net.deltiecord.settings`

The object currently contains UI preferences such as:

```json
{
  "theme_mode": "dark",
  "accent_color": 4285109721,
  "compactness": 0.5,
  "interface_scale": 1.0,
  "font_scale": 1.0,
  "timeline_chunk_size": 30,
  "timeline_chunk_cap": 3,
  "shortcut_bindings": { "openSettings": "control+comma" },
  "collapsed_channel_categories": {
    "!space:example.org": ["category-456"]
  }
}
```

It also stores notification/privacy toggles, panel sizes, selected font names,
read-receipt threshold, RTC processing choices, preferred device IDs, local
participant volumes, and other Deltiecord presentation preferences. Unknown
keys are preserved where possible. Other clients can ignore the entire event.
It contains no passwords, access tokens, recovery keys, media keys, or drafts.

## Extensible profile fields

Deltiecord checks the homeserver's `m.profile_fields` capability before writing
extended fields. Unsupported fields remain unavailable rather than being
silently placed in account data.

| Field | Value | Fallback |
| --- | --- | --- |
| `m.tz` | IANA timezone identifier, for example `Europe/Amsterdam` | Omit timezone/local time |
| `net.deltiecord.bio` | Plain UTF-8 biography text | Omit About section |
| `net.deltiecord.pronouns` | Plain UTF-8 pronoun text | Omit pronoun label |
| `net.deltiecord.banner` | `mxc://` URI for the profile banner | Render colour/empty banner |
| `net.deltiecord.profile_color` | `#RRGGBB` primary colour | Use application accent |
| `net.deltiecord.profile_color_secondary` | `#RRGGBB` secondary gradient colour | Use primary colour |

Display name and avatar use standard Matrix profile fields. Presence and the
short status message use standard Matrix presence APIs. A homeserver or client
that ignores the custom fields still sees a normal Matrix profile.
