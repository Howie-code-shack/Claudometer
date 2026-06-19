import AppKit
import Carbon

// MARK: - Global ⌘U hotkey (Carbon)
//
// RegisterEventHotKey does NOT require Accessibility permission (unlike a global
// NSEvent monitor or CGEventTap), so no prompt is needed. The previous version
// leaked: it installed a fresh event handler on every enable but only ever
// unregistered the hot key, so toggling the setting accumulated handlers and
// fired the callback multiple times per keypress. This version installs the
// handler and the hot key together and tears both down on disable.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onTrigger: () -> Void

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    func register() {
        guard hotKeyRef == nil else { return }   // already registered

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onTrigger() }
            return noErr
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, selfPtr, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: 0x436C5542 /* 'ClUB' */, id: 1)
        let keyCode: UInt32 = 32        // 'U'
        let modifiers = UInt32(cmdKey)  // ⌘
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    deinit {
        unregister()
    }
}
