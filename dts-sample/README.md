# PasteTest

Minimal sample project demonstrating CGEvent.post usage in a sandboxed Mac app.

## What it does

1. Writes "Hello from PasteTest" to NSPasteboard.general
2. Hides the app so the previous app becomes frontmost
3. Posts a ⌘V keystroke via CGEvent.post(tap: .cgSessionEventTap)

This simulates the core behavior of our clipboard manager app (Clipnyx), which was rejected under Guideline 2.4.5.

## How to test

1. Build and run the project in Xcode
2. Open a text editor (e.g. TextEdit) and place your cursor in the document
3. Switch back to PasteTest
4. Click "Copy text & simulate ⌘V"
5. Grant permission when prompted (System Settings > Privacy & Security > Accessibility)
6. The app hides, the text editor becomes active, and "Hello from PasteTest" is pasted

## Key point

This app requires `kTCCServicePostEvent` (CGEvent.post), NOT `kTCCServiceAccessibility` (AXUIElement). No Accessibility framework APIs are used. However, both permissions appear under "Accessibility" in System Settings.
