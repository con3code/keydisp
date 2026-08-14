import Carbon
import Foundation

/// 表示/非表示切替え用グローバルホットキー（Carbon RegisterEventHotKey）
final class HotKeyManager {
    static let shared = HotKeyManager()

    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    func register(keyCode: Int, carbonModifiers: Int) {
        unregister()
        installHandlerIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B44_5350), id: 1) // 'KDSP'
        let status = RegisterEventHotKey(
            UInt32(keyCode), UInt32(carbonModifiers), hotKeyID,
            GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr { hotKeyRef = ref }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, _, userData in
            if let userData {
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onHotKey?() }
            }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
    }
}
