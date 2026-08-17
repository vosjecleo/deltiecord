# Known issues

### Bugs
Universal:
- After first login, the user panel (bottom left) does not appear to load status, avatar and others.
- The app logo should be shifted up somewhat
- Rich/video embeds still have issues
- Settings show other OS specific settings, like GTK border decor setting showing on Windows and Android.
  
Desktop Specific:
- Edited messages show as their unedited counterpart in replies.
- Drag and drop grip pads are mismatched.
![grip-pad-bug.png](./bugs/grip-pad-bug.png)
- Drag drop accidents are easy, please hide drag-drop behind a settings toggle.
  
Mobile Specific:
- Mic Test option crashes the app.
- The app logo has a thick white border
- Profile refresh button touches the edit button (spacing with those three buttons need to be unified)
- No UnifiedPush settings
- Clicking on a settings page causes text to overlap weirdly, animations are botched.
- Too much padding on the bottom of the screen in the Rooms menu
- Edited messages show as their unedited counterpart only.
- Server avatars are circular in their squarcle frames, unlike desktop, where they fill the whole frame.
- In-timeline avatars are verticall squashed/horizontally stretched into an oval shape.
- Padding between message and avatar and avatar and left- hand screen border is unequal.
- Updating the app results in "App not installed" on Android
- Server/Space editing is currently not possible. Long-click on the server should reveal the desktop right-click menu

### Features queued
- Checking for client updates.
- Adding drag-drop channel management to Android via a drag-drop channel management button in server settings.
