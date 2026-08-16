    • Timeline navigation becomes unstable when browsing old history — HIGH 
        ◦ After loading sufficiently old chunks, the timeline sometimes jumps downward unexpectedly. 
        ◦ After this occurs, scrolling upward and then downward can cause the viewport to repeatedly jump upward by ~2–3 message rows, effectively preventing navigation toward newer messages. 
        ◦ Appears related to chunk loading/window management, but can continue even when no chunks are actively being unloaded. 
        ◦ Suspect scroll-anchor / scroll-extent correction / widget-height changes rather than simply the chunk eviction policy. 
        ◦ This is probably your nastiest current single-user bug. 
    • Reply navigation becomes incorrect after repeated use — HIGH 
        ◦ First “jump to replied message” generally works. 
        ◦ Second or subsequent reply jumps in the same timeline may navigate to seemingly unrelated messages. 
        ◦ Strong smell of stale event→index mapping, reused anchor state, or timeline-window reconstruction retaining old coordinates. 
    • Deltiecord profiles initially render as incomplete generic profiles — MEDIUM 
        ◦ Clicking a profile first displays an empty/non-Deltiecord-looking card. 
        ◦ Custom/extensible profile data appears afterward. 
        ◦ Ideally hold the popup in a tiny loading state or populate it from cache before showing it instead of flashing incorrect content. 
    • Member list presentation is inconsistent — UX 
        ◦ Member list currently appears as an overlay/popup. 
        ◦ It should use the existing right-hand panel and toggle between Profile / Members, depending on context. 
        ◦ That’ll actually simplify the mental model of the layout. 
    • Escape does not close Settings — LOW but annoying 
        ◦ Should follow the app-wide Escape convention. 
    • Audio output device cannot be selected — MEDIUM 
        ◦ Input selection exists; output selection currently does not function. 
    • Notification/call sounds appear broken — MEDIUM 
        ◦ No audible notification/call sounds. 
        ◦ Deltiecord apparently does not appear as an audio source in Helvum/PipeWire. 
        ◦ That latter observation is useful: it suggests this may be deeper than “wrong volume,” perhaps the sound service never creates a playback stream at all. 
    • Keyboard shortcuts appear nonfunctional — HIGH-ish 
        ◦ Configurable shortcuts can be defined but apparently don't trigger. 
        ◦ Test focus-sensitive cases too; if they work only when some root widget owns focus, that would explain why they seem entirely dead. 
    • Search/reply navigation lacks target feedback — UX 
        ◦ When jumping to a message from Search or Replies, blink/highlight the target message row twice using the darker hover/selected background. 
        ◦ I like this. Without it, even a technically correct jump can leave you thinking “okay… which message?” 
    • Compact profiles omit local time — LOW 
        ◦ Full profiles show timezone/local time; compact cards should too. 
    • No microphone test — FEATURE/UX 
        ◦ Add a microphone-test area with input level and local playback. 
        ◦ Ideally allow toggling echo cancellation/noise suppression/etc. while testing, because otherwise you can’t meaningfully tell whether those controls actually do anything.
    • Drag/drop room ordering inside a Space 
    • reorder text rooms and voice rooms directly in the sidebar 
    • persist the order in Matrix room/Space state 
    • show a clear insertion marker while dragging 
    • ideally allow moving rooms between categories/dividers too 
    • Channel categories/dividers 
    • Discord-style collapsible sections like TEXT CHANNELS, VOICE, GAMES, etc. 
    • category names editable 
    • drag rooms into/out of them 
    • categories themselves reorderable 
    • collapsed state local per-client/account preference 
    • don’t break Matrix interoperability if another client ignores the category metadata


