import AppKit
import Carbon
import Combine
import SwiftUI
import UniformTypeIdentifiers

private enum AppMetadata {
    static let name = "myDAY"
    static let developer = "qianyushi"
    static let repositoryDisplay = "github.com/QianYushi/myDAY"
    static let repositoryURL = URL(string: "https://github.com/QianYushi/myDAY")!
    static let latestReleaseURL = URL(string: "https://github.com/QianYushi/myDAY/releases/latest")!
    static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/QianYushi/myDAY/releases/latest")!

    static var versionDisplay: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let version, let build, !version.isEmpty, !build.isEmpty {
            return "\(version) (\(build))"
        }
        return version ?? build ?? "未知版本"
    }

    static var shortVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }
}

@main
enum QuadrantDesktopMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate

        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = BoardStore()
    private let windowModeStore = WindowModeStore()
    private var windowController: DesktopWindowController?
    private var hotKeyManager: QuadrantHotKeyManager?
    private var aboutWindowController: AboutWindowController?
    private var shortcutSettingsWindowController: ShortcutSettingsWindowController?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var windowModeCancellable: AnyCancellable?
    private var shortcutChangeCancellable: AnyCancellable?
    private var appDesktopModeItem: NSMenuItem?
    private var appNormalModeItem: NSMenuItem?
    private var statusShowWindowItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureApplicationMenu()

        let controller = DesktopWindowController(store: store, windowModeStore: windowModeStore)
        windowController = controller
        controller.showForCurrentMode()

        configureStatusItem()
        observeWindowMode()
        observeShortcuts()
        configureHotKeys()
    }

    private func configureApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu(title: AppMetadata.name)
        let appDesktopModeItem = makeModeMenuItem(for: .desktopResident)
        let appNormalModeItem = makeModeMenuItem(for: .normalWindow)
        self.appDesktopModeItem = appDesktopModeItem
        self.appNormalModeItem = appNormalModeItem
        appMenu.addItem(NSMenuItem(title: "关于 \(AppMetadata.name)", action: #selector(showAboutFromMenu), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(appDesktopModeItem)
        appMenu.addItem(appNormalModeItem)
        appMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(closeWindowFromMenu), keyEquivalent: "w"))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "快捷键设置…", action: #selector(showShortcutSettingsFromMenu), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSStandardKeyBindingResponding.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = StatusIcon.makeImage()
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusMenu = makeStatusMenu()
        self.statusItem = statusItem
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu(title: AppMetadata.name)
        menu.showsStateColumn = false

        let showWindowItem = makeStatusActionItem(title: "展示到前台", action: #selector(showWindowFromMenu))
        statusShowWindowItem = showWindowItem
        menu.addItem(showWindowItem)
        menu.addItem(makeStatusActionItem(title: "隐藏窗口", action: #selector(hideWindowFromMenu)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeStatusActionItem(title: "快捷键设置…", action: #selector(showShortcutSettingsFromMenu)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeStatusActionItem(title: "关于 \(AppMetadata.name)", action: #selector(showAboutFromMenu)))
        let quitItem = makeStatusActionItem(title: "退出", action: #selector(terminateFromStatusMenu))
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)
        updateStatusShowWindowShortcut()
        return menu
    }

    private func makeStatusActionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = nil
        item.state = .off
        return item
    }

    private func makeModeMenuItem(for mode: WindowDisplayMode) -> NSMenuItem {
        let selector: Selector
        switch mode {
        case .desktopResident:
            selector = #selector(selectDesktopResidentModeFromMenu)
        case .normalWindow:
            selector = #selector(selectNormalWindowModeFromMenu)
        }
        let item = NSMenuItem(title: mode.title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func observeWindowMode() {
        windowModeCancellable = windowModeStore.$mode.sink { [weak self] _ in
            self?.updateModeMenuItems()
        }
    }

    private func updateModeMenuItems() {
        let mode = windowModeStore.mode
        appDesktopModeItem?.state = mode == .desktopResident ? .on : .off
        appNormalModeItem?.state = mode == .normalWindow ? .on : .off
    }

    private func observeShortcuts() {
        shortcutChangeCancellable = NotificationCenter.default
            .publisher(for: .quadrantDesktopShortcutsDidChange)
            .sink { [weak self] _ in
                self?.updateStatusShowWindowShortcut()
            }
    }

    private func updateStatusShowWindowShortcut() {
        guard let statusShowWindowItem else { return }
        guard let shortcut = QuadrantShortcut.loadShowWindow() else {
            statusShowWindowItem.keyEquivalent = ""
            statusShowWindowItem.keyEquivalentModifierMask = []
            return
        }

        statusShowWindowItem.keyEquivalent = shortcut.menuKeyEquivalent
        statusShowWindowItem.keyEquivalentModifierMask = shortcut.menuModifierMask
    }

    private func configureHotKeys() {
        let manager = QuadrantHotKeyManager(
            onShortcut: { [weak self] quadrant in
                self?.windowController?.showForCurrentMode()
                self?.store.requestAdd(to: quadrant)
            },
            onShowWindow: { [weak self] in
                self?.windowController?.showForCurrentMode()
            }
        )
        hotKeyManager = manager
        manager.start()
    }

    @objc private func selectDesktopResidentModeFromMenu() {
        windowModeStore.setMode(.desktopResident)
        windowController?.showForCurrentMode()
    }

    @objc private func selectNormalWindowModeFromMenu() {
        windowModeStore.setMode(.normalWindow)
        windowController?.showForCurrentMode()
    }

    @objc private func statusItemClicked() {
        if let statusMenu {
            statusItem?.popUpMenu(statusMenu)
        }
    }

    @objc private func closeWindowFromMenu() {
        windowController?.closeWindow()
    }

    @objc private func showWindowFromMenu() {
        statusMenu?.cancelTracking()

        DispatchQueue.main.async { [weak self] in
            self?.windowController?.showForCurrentMode()
        }
    }

    @objc private func hideWindowFromMenu() {
        windowController?.closeWindow()
    }

    @objc private func terminateFromStatusMenu() {
        NSApp.terminate(nil)
    }

    @objc private func showAboutFromMenu() {
        statusMenu?.cancelTracking()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if aboutWindowController == nil {
                aboutWindowController = AboutWindowController()
            }
            aboutWindowController?.show()
        }
    }

    @objc private func showShortcutSettingsFromMenu() {
        statusMenu?.cancelTracking()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if shortcutSettingsWindowController == nil {
                shortcutSettingsWindowController = ShortcutSettingsWindowController()
            }
            shortcutSettingsWindowController?.show()
        }
    }
}

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class FocusSinkHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
}

enum WindowDisplayMode: String, CaseIterable {
    case desktopResident
    case normalWindow

    var title: String {
        switch self {
        case .desktopResident:
            return "桌面常驻模式"
        case .normalWindow:
            return "正常窗口模式"
        }
    }
}

@MainActor
final class WindowModeStore: ObservableObject {
    private static let defaultsKey = "quadrantDesktop.windowMode"

    @Published private(set) var mode: WindowDisplayMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: Self.defaultsKey)
        }
    }

    init() {
        if
            let rawValue = UserDefaults.standard.string(forKey: Self.defaultsKey),
            let mode = WindowDisplayMode(rawValue: rawValue)
        {
            self.mode = mode
        } else {
            mode = .desktopResident
        }
    }

    func setMode(_ mode: WindowDisplayMode) {
        guard self.mode != mode else { return }
        self.mode = mode
    }
}

@MainActor
final class DesktopWindowController: NSWindowController, NSWindowDelegate {
    private static let frameAutosaveName = "QuadrantDesktopWindowFrame"
    private let store: BoardStore
    private let windowModeStore: WindowModeStore
    private var settleTask: Task<Void, Never>?
    private var windowModeCancellable: AnyCancellable?

    init(store: BoardStore, windowModeStore: WindowModeStore) {
        self.store = store
        self.windowModeStore = windowModeStore

        let initialFrame = Self.defaultFrame()
        let window = DesktopWindow(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        let rootView = ContentView(store: store, windowModeStore: windowModeStore)
        let hostingView = FocusSinkHostingView(rootView: rootView)
        window.contentView = hostingView
        window.initialFirstResponder = hostingView
        window.title = ""
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = NSSize(width: 680, height: 440)
        window.setFrameAutosaveName(Self.frameAutosaveName)

        super.init(window: window)

        window.delegate = self
        applyMode(windowModeStore.mode, showWindow: false)
        windowModeCancellable = windowModeStore.$mode.dropFirst().sink { [weak self] mode in
            self?.applyMode(mode, showWindow: true)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showForCurrentMode() {
        switch windowModeStore.mode {
        case .desktopResident:
            raiseForEditing()
        case .normalWindow:
            showNormalWindow()
        }
    }

    func resetFrame() {
        guard let window else { return }
        window.setFrame(Self.defaultFrame(), display: true, animate: true)
        window.saveFrame(usingName: Self.frameAutosaveName)
        showForCurrentMode()
    }

    func closeWindow() {
        settleTask?.cancel()
        window?.orderOut(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        switch windowModeStore.mode {
        case .desktopResident:
            raiseForEditing(activateApp: false)
        case .normalWindow:
            applyNormalWindowBehavior()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if windowModeStore.mode == .desktopResident {
            scheduleDesktopSettle()
        } else {
            settleTask?.cancel()
        }
    }

    func windowDidResize(_ notification: Notification) {
        applyCurrentWindowBehavior()
    }

    func windowDidMove(_ notification: Notification) {
        applyCurrentWindowBehavior()
    }

    private func applyMode(_ mode: WindowDisplayMode, showWindow: Bool) {
        switch mode {
        case .desktopResident:
            if showWindow {
                raiseForEditing()
            } else {
                settleOnDesktop()
            }
        case .normalWindow:
            applyNormalWindowBehavior()
            if showWindow {
                showNormalWindow()
            }
        }
    }

    private func applyCurrentWindowBehavior() {
        switch windowModeStore.mode {
        case .desktopResident:
            applyDesktopResidentWindowBehavior()
        case .normalWindow:
            applyNormalWindowBehavior()
        }
    }

    private func applyDesktopResidentWindowBehavior() {
        guard let window else { return }
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary
        ]
        window.canHide = false
        window.isExcludedFromWindowsMenu = true
    }

    private func applyNormalWindowBehavior() {
        settleTask?.cancel()
        guard let window else { return }
        window.collectionBehavior = []
        window.canHide = true
        window.isExcludedFromWindowsMenu = false
        window.level = .normal
    }

    private func raiseForEditing(activateApp: Bool = true) {
        guard windowModeStore.mode == .desktopResident else {
            showNormalWindow(activateApp: activateApp)
            return
        }

        settleTask?.cancel()
        applyDesktopResidentWindowBehavior()
        guard let window else { return }

        window.level = .floating
        window.orderFrontRegardless()

        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
        }
    }

    private func showNormalWindow(activateApp: Bool = true) {
        applyNormalWindowBehavior()
        guard let window else { return }

        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
        } else {
            window.orderFront(nil)
        }
    }

    private func scheduleDesktopSettle() {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.settleOnDesktop()
        }
    }

    private func settleOnDesktop() {
        settleTask?.cancel()
        guard windowModeStore.mode == .desktopResident else { return }
        applyDesktopResidentWindowBehavior()
        guard let window else { return }

        let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        window.level = NSWindow.Level(rawValue: desktopIconLevel + 1)
        window.orderFrontRegardless()
    }

    private static func defaultFrame() -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(max(visibleFrame.width * 0.62, 860), 1180)
        let height = min(max(visibleFrame.height * 0.68, 600), 820)
        let x = visibleFrame.midX - width / 2
        let y = visibleFrame.midY - height / 2
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

enum QuadrantID: String, CaseIterable, Codable, Identifiable {
    case q1
    case q2
    case q3
    case q4

    var id: String { rawValue }

    var shortcutName: String {
        switch self {
        case .q1: return "重要紧急"
        case .q2: return "重要不紧急"
        case .q3: return "不重要紧急"
        case .q4: return "不重要不紧急"
        }
    }
}

struct Todo: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    var done: Bool
    var completedAt: Date?
    var due: String?
    var note: String?

    init(id: UUID = UUID(), text: String, done: Bool = false, completedAt: Date? = nil, due: String? = nil, note: String? = nil) {
        self.id = id
        self.text = text
        self.done = done
        self.completedAt = completedAt
        self.due = due
        self.note = note
    }
}

struct Quadrant: Identifiable, Codable, Equatable {
    var id: QuadrantID
    var emoji: String
    var title: String
    var subtitle: String
    var todos: [Todo]

    static func `default`(_ id: QuadrantID) -> Quadrant {
        switch id {
        case .q1:
            return Quadrant(id: id, emoji: "🔥", title: "重要紧急", subtitle: "立即做", todos: [])
        case .q2:
            return Quadrant(id: id, emoji: "⭐", title: "重要不紧急", subtitle: "计划做", todos: [])
        case .q3:
            return Quadrant(id: id, emoji: "👥", title: "不重要紧急", subtitle: "委托做", todos: [])
        case .q4:
            return Quadrant(id: id, emoji: "🗑️", title: "不重要不紧急", subtitle: "不做", todos: [])
        }
    }
}

struct BoardState: Codable, Equatable {
    var quadrants: [Quadrant]
    var splitX: Double
    var splitY: Double

    static var blank: BoardState {
        BoardState(
            quadrants: QuadrantID.allCases.map { Quadrant.default($0) },
            splitX: 0.5,
            splitY: 0.5
        )
    }
}

extension Notification.Name {
    static let quadrantDesktopShortcutsDidChange = Notification.Name("quadrantDesktopShortcutsDidChange")
    static let quadrantDesktopShortcutRecordingDidStart = Notification.Name("quadrantDesktopShortcutRecordingDidStart")
    static let quadrantDesktopShortcutRecordingDidEnd = Notification.Name("quadrantDesktopShortcutRecordingDidEnd")
}

enum QuadrantDefaultsKey {
    static let showWindowShortcut = "quadrantDesktop.shortcut.showWindow"

    static func shortcut(_ id: QuadrantID) -> String {
        "quadrantDesktop.shortcut.\(id.rawValue)"
    }
}

struct QuadrantShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifierFlags: UInt32
    let keyDisplay: String

    var displayString: String {
        var parts: [String] = []
        if modifierFlags & UInt32(controlKey) != 0 {
            parts.append("⌃")
        }
        if modifierFlags & UInt32(optionKey) != 0 {
            parts.append("⌥")
        }
        if modifierFlags & UInt32(shiftKey) != 0 {
            parts.append("⇧")
        }
        if modifierFlags & UInt32(cmdKey) != 0 {
            parts.append("⌘")
        }
        return parts.joined() + keyDisplay
    }

    var menuKeyEquivalent: String {
        switch Int(keyCode) {
        case kVK_Space:
            return " "
        case kVK_Return:
            return "\r"
        case kVK_Tab:
            return "\t"
        case kVK_Delete:
            return Self.menuFunctionKey(NSDeleteCharacter)
        case kVK_ForwardDelete:
            return Self.menuFunctionKey(NSDeleteFunctionKey)
        case kVK_LeftArrow:
            return Self.menuFunctionKey(NSLeftArrowFunctionKey)
        case kVK_RightArrow:
            return Self.menuFunctionKey(NSRightArrowFunctionKey)
        case kVK_UpArrow:
            return Self.menuFunctionKey(NSUpArrowFunctionKey)
        case kVK_DownArrow:
            return Self.menuFunctionKey(NSDownArrowFunctionKey)
        default:
            return keyDisplay.count == 1 ? keyDisplay.lowercased() : ""
        }
    }

    var menuModifierMask: NSEvent.ModifierFlags {
        var result: NSEvent.ModifierFlags = []
        if modifierFlags & UInt32(controlKey) != 0 {
            result.insert(.control)
        }
        if modifierFlags & UInt32(optionKey) != 0 {
            result.insert(.option)
        }
        if modifierFlags & UInt32(shiftKey) != 0 {
            result.insert(.shift)
        }
        if modifierFlags & UInt32(cmdKey) != 0 {
            result.insert(.command)
        }
        return result
    }

    init(keyCode: UInt32, modifierFlags: UInt32, keyDisplay: String) {
        self.keyCode = keyCode
        self.modifierFlags = modifierFlags
        self.keyDisplay = keyDisplay
    }

    init?(event: NSEvent) {
        let modifierFlags = Self.carbonModifierFlags(from: event.modifierFlags)
        guard modifierFlags != 0 else {
            return nil
        }

        let keyDisplay = Self.keyDisplay(for: event)
        guard !keyDisplay.isEmpty else {
            return nil
        }

        self.keyCode = UInt32(event.keyCode)
        self.modifierFlags = modifierFlags
        self.keyDisplay = keyDisplay
    }

    static func load(for quadrant: QuadrantID, defaults: UserDefaults = .standard) -> QuadrantShortcut? {
        guard let data = defaults.data(forKey: QuadrantDefaultsKey.shortcut(quadrant)) else {
            return nil
        }
        return try? JSONDecoder().decode(QuadrantShortcut.self, from: data)
    }

    static func loadShowWindow(defaults: UserDefaults = .standard) -> QuadrantShortcut? {
        guard let data = defaults.data(forKey: QuadrantDefaultsKey.showWindowShortcut) else {
            return nil
        }
        return try? JSONDecoder().decode(QuadrantShortcut.self, from: data)
    }

    func save(for quadrant: QuadrantID, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }
        defaults.set(data, forKey: QuadrantDefaultsKey.shortcut(quadrant))
        NotificationCenter.default.post(name: .quadrantDesktopShortcutsDidChange, object: nil)
    }

    func saveForShowWindow(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else {
            return
        }
        defaults.set(data, forKey: QuadrantDefaultsKey.showWindowShortcut)
        NotificationCenter.default.post(name: .quadrantDesktopShortcutsDidChange, object: nil)
    }

    static func clear(for quadrant: QuadrantID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: QuadrantDefaultsKey.shortcut(quadrant))
        NotificationCenter.default.post(name: .quadrantDesktopShortcutsDidChange, object: nil)
    }

    static func clearShowWindow(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: QuadrantDefaultsKey.showWindowShortcut)
        NotificationCenter.default.post(name: .quadrantDesktopShortcutsDidChange, object: nil)
    }

    private static func carbonModifierFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) {
            result |= UInt32(controlKey)
        }
        if flags.contains(.option) {
            result |= UInt32(optionKey)
        }
        if flags.contains(.shift) {
            result |= UInt32(shiftKey)
        }
        if flags.contains(.command) {
            result |= UInt32(cmdKey)
        }
        return result
    }

    private static func keyDisplay(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space:
            return "Space"
        case kVK_Return:
            return "Return"
        case kVK_Tab:
            return "Tab"
        case kVK_Delete:
            return "Delete"
        case kVK_ForwardDelete:
            return "Forward Delete"
        case kVK_LeftArrow:
            return "←"
        case kVK_RightArrow:
            return "→"
        case kVK_UpArrow:
            return "↑"
        case kVK_DownArrow:
            return "↓"
        case kVK_Escape:
            return "Esc"
        default:
            let characters = event.charactersIgnoringModifiers ?? ""
            return characters.uppercased()
        }
    }

    private static func menuFunctionKey(_ key: Int) -> String {
        String(UnicodeScalar(UInt32(key))!)
    }
}

final class QuadrantHotKeyManager {
    private static let signature = fourCharCode("qdrt")
    private static let showWindowHotKeyID: UInt32 = 100

    private let onShortcut: @MainActor (QuadrantID) -> Void
    private let onShowWindow: @MainActor () -> Void
    private var eventHandler: EventHandlerRef?
    private var registeredHotKeys: [UInt32: EventHotKeyRef] = [:]
    private var shortcutsDidChangeObserver: NSObjectProtocol?
    private var recordingDidStartObserver: NSObjectProtocol?
    private var recordingDidEndObserver: NSObjectProtocol?
    private var isPausedForRecording = false

    init(
        onShortcut: @escaping @MainActor (QuadrantID) -> Void,
        onShowWindow: @escaping @MainActor () -> Void
    ) {
        self.onShortcut = onShortcut
        self.onShowWindow = onShowWindow
    }

    deinit {
        stop()
    }

    func start() {
        guard eventHandler == nil else { return }
        startObservers()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            Self.handleHotKeyEvent,
            1,
            &eventType,
            userData,
            &eventHandler
        )
        guard status == noErr else {
            eventHandler = nil
            return
        }

        reloadHotKeys()
    }

    func stop() {
        unregisterHotKeys()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }

        stopObservers()
    }

    private func startObservers() {
        guard shortcutsDidChangeObserver == nil,
              recordingDidStartObserver == nil,
              recordingDidEndObserver == nil else {
            return
        }

        shortcutsDidChangeObserver = NotificationCenter.default.addObserver(
            forName: .quadrantDesktopShortcutsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadHotKeys()
        }

        recordingDidStartObserver = NotificationCenter.default.addObserver(
            forName: .quadrantDesktopShortcutRecordingDidStart,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isPausedForRecording = true
            self?.unregisterHotKeys()
        }

        recordingDidEndObserver = NotificationCenter.default.addObserver(
            forName: .quadrantDesktopShortcutRecordingDidEnd,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isPausedForRecording = false
            self?.reloadHotKeys()
        }
    }

    private func stopObservers() {
        let notificationCenter = NotificationCenter.default
        if let shortcutsDidChangeObserver {
            notificationCenter.removeObserver(shortcutsDidChangeObserver)
            self.shortcutsDidChangeObserver = nil
        }
        if let recordingDidStartObserver {
            notificationCenter.removeObserver(recordingDidStartObserver)
            self.recordingDidStartObserver = nil
        }
        if let recordingDidEndObserver {
            notificationCenter.removeObserver(recordingDidEndObserver)
            self.recordingDidEndObserver = nil
        }
    }

    private func reloadHotKeys() {
        guard !isPausedForRecording else { return }

        unregisterHotKeys()

        for quadrant in QuadrantID.allCases {
            guard let shortcut = QuadrantShortcut.load(for: quadrant) else { continue }
            registerHotKey(quadrant, shortcut: shortcut)
        }

        if let shortcut = QuadrantShortcut.loadShowWindow() {
            registerHotKey(id: Self.showWindowHotKeyID, shortcut: shortcut)
        }
    }

    private func unregisterHotKeys() {
        for hotKey in registeredHotKeys.values {
            UnregisterEventHotKey(hotKey)
        }
        registeredHotKeys.removeAll()
    }

    private func registerHotKey(_ quadrant: QuadrantID, shortcut: QuadrantShortcut) {
        registerHotKey(id: quadrant.hotKeyID, shortcut: shortcut)
    }

    private func registerHotKey(id: UInt32, shortcut: QuadrantShortcut) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifierFlags,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else { return }
        registeredHotKeys[id] = hotKeyRef
    }

    private func handleHotKey(id: UInt32) -> OSStatus {
        if id == Self.showWindowHotKeyID {
            Task { @MainActor in
                onShowWindow()
            }
            return noErr
        }

        guard let quadrant = QuadrantID(hotKeyID: id) else {
            return OSStatus(eventNotHandledErr)
        }

        Task { @MainActor in
            onShortcut(quadrant)
        }

        return noErr
    }

    private static let handleHotKeyEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else {
            return OSStatus(eventNotHandledErr)
        }

        var hotKeyID = EventHotKeyID(signature: 0, id: 0)
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == QuadrantHotKeyManager.signature else {
            return OSStatus(eventNotHandledErr)
        }

        let manager = Unmanaged<QuadrantHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
        return manager.handleHotKey(id: hotKeyID.id)
    }

    private static func fourCharCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { code, character in
            (code << 8) + OSType(character)
        }
    }
}

extension QuadrantID {
    fileprivate var hotKeyID: UInt32 {
        switch self {
        case .q1: return 1
        case .q2: return 2
        case .q3: return 3
        case .q4: return 4
        }
    }

    fileprivate init?(hotKeyID: UInt32) {
        switch hotKeyID {
        case 1: self = .q1
        case 2: self = .q2
        case 3: self = .q3
        case 4: self = .q4
        default: return nil
        }
    }
}

@MainActor
final class AboutWindowController: NSWindowController {
    init() {
        let hostingController = NSHostingController(rootView: AboutView())
        let window = NSWindow(contentViewController: hostingController)
        window.title = "关于 \(AppMetadata.name)"
        window.styleMask = [.titled, .closable]
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 500, height: 380)
        window.contentMaxSize = NSSize(width: 500, height: 380)
        window.setContentSize(NSSize(width: 500, height: 380))
        Self.configureCenteredTitle(for: window)
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private static func configureCenteredTitle(for window: NSWindow) {
        guard let closeButton = window.standardWindowButton(.closeButton),
              let titlebarView = closeButton.superview else {
            return
        }

        let titleLabel = NSTextField(labelWithString: "关于 \(AppMetadata.name)")
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titlebarView.addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: titlebarView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: titlebarView.leadingAnchor, constant: 90),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: titlebarView.trailingAnchor, constant: -90)
        ])
    }
}

private struct AboutView: View {
    @ObservedObject private var updateModel: AboutUpdateViewModel

    @MainActor
    init() {
        updateModel = AboutUpdateViewModel()
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 2)
            header
            updateSection
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 32, leading: 34, bottom: 24, trailing: 34))
        .frame(width: 500, height: 380)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(spacing: 13) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 86, height: 86)
                .cornerRadius(19)
                .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 3)

            VStack(spacing: 4) {
                Text(AppMetadata.name)
                    .font(.system(size: 28, weight: .bold))
                Text("当前版本 \(AppMetadata.versionDisplay)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 7) {
                Text("开发者：\(AppMetadata.developer)")
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("GitHub：")
                    Button(AppMetadata.repositoryDisplay) {
                        NSWorkspace.shared.open(AppMetadata.repositoryURL)
                    }
                    .buttonStyle(.link)
                }
            }
            .font(.system(size: 13))
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var updateSection: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.horizontal, 10)

            HStack(spacing: 10) {
                Spacer()

                Button("检查更新") {
                    updateModel.checkForUpdates()
                }
                .disabled(updateModel.isChecking)

                if updateModel.releaseURL != nil {
                    Button("打开发布页") {
                        updateModel.openReleasePage()
                    }
                }

                Spacer()
            }

            if updateModel.isChecking {
                ProgressView()
                    .controlSize(.small)
            }

            Text(updateModel.statusText)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

@MainActor
final class AboutUpdateViewModel: ObservableObject {
    @Published var statusText = "可以检查 GitHub Release 里的最新版。"
    @Published var isChecking = false
    @Published var releaseURL: URL?

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    func checkForUpdates() {
        guard !isChecking else { return }
        isChecking = true
        releaseURL = nil
        statusText = "正在检查更新…"

        Task {
            await performUpdateCheck()
        }
    }

    func openReleasePage() {
        NSWorkspace.shared.open(releaseURL ?? AppMetadata.latestReleaseURL)
    }

    private func performUpdateCheck() async {
        defer { isChecking = false }

        do {
            var request = URLRequest(url: AppMetadata.latestReleaseAPIURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("\(AppMetadata.name)/\(AppMetadata.shortVersion)", forHTTPHeaderField: "User-Agent")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                statusText = "更新服务器暂时不可用。"
                return
            }

            if httpResponse.statusCode == 404 {
                statusText = "当前还没有发布版本。"
                return
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                statusText = "检查更新失败：GitHub 返回 \(httpResponse.statusCode)。"
                return
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            releaseURL = release.htmlURL

            if Self.isVersion(release.tagName, newerThan: AppMetadata.shortVersion) {
                statusText = "发现新版本 \(release.tagName)，可以打开发布页下载。"
            } else {
                statusText = "当前已经是最新版本。"
            }
        } catch {
            statusText = "检查更新失败：\(error.localizedDescription)"
        }
    }

    private static func isVersion(_ latest: String, newerThan current: String) -> Bool {
        let latestParts = versionParts(latest)
        let currentParts = versionParts(current)
        let count = max(latestParts.count, currentParts.count)

        for index in 0..<count {
            let latestValue = latestParts[safe: index] ?? 0
            let currentValue = currentParts[safe: index] ?? 0
            if latestValue != currentValue {
                return latestValue > currentValue
            }
        }

        return false
    }

    private static func versionParts(_ value: String) -> [Int] {
        value
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: ".")
            .map { part in
                let digits = part.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }
    }
}

@MainActor
final class ShortcutSettingsWindowController: NSWindowController {
    private let viewModel = ShortcutSettingsViewModel()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "快捷键"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ShortcutSettingsView(viewModel: viewModel))
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}

enum ShortcutSettingsTarget: Hashable, Identifiable {
    case showWindow
    case quadrant(QuadrantID)

    var id: String {
        switch self {
        case .showWindow:
            return "showWindow"
        case .quadrant(let quadrant):
            return quadrant.id
        }
    }

    var title: String {
        switch self {
        case .showWindow:
            return "前台展示窗口"
        case .quadrant(let quadrant):
            return quadrant.shortcutName
        }
    }
}

@MainActor
final class ShortcutSettingsViewModel: ObservableObject {
    @Published private(set) var shortcuts: [ShortcutSettingsTarget: QuadrantShortcut?] = [:]
    @Published var recordingTarget: ShortcutSettingsTarget?
    @Published var statusText = "默认不占用快捷键。点击录制后按下新的组合键，Esc 取消。"

    private var keyEventMonitor: Any?

    init() {
        reload()
    }

    deinit {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
        }
        NotificationCenter.default.post(name: .quadrantDesktopShortcutRecordingDidEnd, object: nil)
    }

    func displayString(for target: ShortcutSettingsTarget) -> String {
        guard let shortcut = cachedShortcut(for: target) else {
            return "未设置"
        }
        return shortcut.displayString
    }

    func isClearDisabled(for target: ShortcutSettingsTarget) -> Bool {
        cachedShortcut(for: target) == nil
    }

    func record(_ target: ShortcutSettingsTarget) {
        stopRecording()
        recordingTarget = target
        statusText = "正在录制 \(target.title)：按下新的快捷键…"
        NotificationCenter.default.post(name: .quadrantDesktopShortcutRecordingDidStart, object: nil)

        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
            return nil
        }
    }

    func clear(_ target: ShortcutSettingsTarget) {
        if recordingTarget == target {
            stopRecording()
        }
        clearShortcut(for: target)
        shortcuts[target] = nil
        statusText = "\(target.title) 已设为未设置。"
    }

    private func reload() {
        var reloaded: [ShortcutSettingsTarget: QuadrantShortcut?] = [:]
        if let shortcut = QuadrantShortcut.loadShowWindow() {
            reloaded[.showWindow] = shortcut
        }
        for quadrant in QuadrantID.allCases {
            let target = ShortcutSettingsTarget.quadrant(quadrant)
            if let shortcut = QuadrantShortcut.load(for: quadrant) {
                reloaded[target] = shortcut
            }
        }
        shortcuts = reloaded
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard event.keyCode != UInt16(kVK_Escape) else {
            stopRecording()
            statusText = "已取消录制。"
            return
        }

        guard let target = recordingTarget else { return }

        guard let shortcut = QuadrantShortcut(event: event) else {
            statusText = "快捷键至少需要包含一个修饰键。"
            return
        }

        save(shortcut, for: target)
        shortcuts[target] = shortcut
        stopRecording()
        statusText = "\(target.title) 已设置为 \(shortcut.displayString)。"
    }

    private func cachedShortcut(for target: ShortcutSettingsTarget) -> QuadrantShortcut? {
        if let value = shortcuts[target] {
            return value
        }
        return nil
    }

    private func save(_ shortcut: QuadrantShortcut, for target: ShortcutSettingsTarget) {
        switch target {
        case .showWindow:
            shortcut.saveForShowWindow()
        case .quadrant(let quadrant):
            shortcut.save(for: quadrant)
        }
    }

    private func clearShortcut(for target: ShortcutSettingsTarget) {
        switch target {
        case .showWindow:
            QuadrantShortcut.clearShowWindow()
        case .quadrant(let quadrant):
            QuadrantShortcut.clear(for: quadrant)
        }
    }

    private func stopRecording() {
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }

        if recordingTarget != nil {
            recordingTarget = nil
            NotificationCenter.default.post(name: .quadrantDesktopShortcutRecordingDidEnd, object: nil)
        }
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var viewModel: ShortcutSettingsViewModel
    private let targets: [ShortcutSettingsTarget] = [.showWindow] + QuadrantID.allCases.map { .quadrant($0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("快捷键")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Palette.text)

            VStack(spacing: 8) {
                ForEach(targets) { target in
                    ShortcutRow(
                        title: target.title,
                        shortcut: viewModel.displayString(for: target),
                        isRecording: viewModel.recordingTarget == target,
                        clearDisabled: viewModel.isClearDisabled(for: target),
                        onRecord: { viewModel.record(target) },
                        onClear: { viewModel.clear(target) }
                    )
                }
            }

            Text(viewModel.statusText)
                .font(.system(size: 12))
                .foregroundStyle(Palette.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(22)
        .frame(width: 420)
        .background(Palette.background)
    }
}

struct ShortcutRow: View {
    let title: String
    let shortcut: String
    let isRecording: Bool
    let clearDisabled: Bool
    let onRecord: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Palette.text)
                .frame(width: 108, alignment: .leading)

            Text(isRecording ? "按键中…" : shortcut)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(isRecording ? Palette.accent : Palette.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Palette.softBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))

            Button("录制", action: onRecord)
                .buttonStyle(.bordered)

            Button("清除", action: onClear)
                .buttonStyle(.borderless)
                .disabled(clearDisabled)
        }
    }
}

@MainActor
final class BoardStore: ObservableObject {
    private static let defaultsKey = "quadrantDesktop.board.v1"
    private var flashTask: Task<Void, Never>?
    private var suppressBlankAddUntil = Date.distantPast

    @Published var board: BoardState {
        didSet { save() }
    }

    @Published var addTarget: QuadrantID?
    @Published var addRequestSerial = 0
    @Published var flashQuadrant: QuadrantID?
    @Published var activeAddQuadrant: QuadrantID?
    @Published var activeAddDraft = ""

    init() {
        if
            let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
            let decoded = try? JSONDecoder().decode(BoardState.self, from: data),
            !decoded.quadrants.isEmpty
        {
            board = Self.normalized(decoded)
        } else {
            board = .blank
        }
    }

    var totalTodos: Int {
        board.quadrants.reduce(0) { $0 + $1.todos.count }
    }

    var doneTodos: Int {
        board.quadrants.reduce(0) { $0 + $1.todos.filter(\.done).count }
    }

    func quadrant(_ id: QuadrantID) -> Quadrant {
        board.quadrants.first { $0.id == id } ?? .default(id)
    }

    func todo(_ id: UUID) -> Todo? {
        for quadrant in board.quadrants {
            if let todo = quadrant.todos.first(where: { $0.id == id }) {
                return todo
            }
        }
        return nil
    }

    func requestAdd(to id: QuadrantID) {
        addTarget = id
        addRequestSerial += 1
        suppressBlankAddUntil = .distantPast
        activeAddQuadrant = id
        activeAddDraft = ""
        flashQuadrant = id
        flashTask?.cancel()
        flashTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 550_000_000)
            guard !Task.isCancelled, self?.flashQuadrant == id else { return }
            self?.flashQuadrant = nil
        }
    }

    func beginAddFromBlankTap(to id: QuadrantID) -> Bool {
        guard Date() >= suppressBlankAddUntil else {
            return false
        }

        if activeAddQuadrant != nil {
            return false
        }

        activeAddQuadrant = id
        activeAddDraft = ""
        return true
    }

    func activateAdd(to id: QuadrantID) {
        suppressBlankAddUntil = .distantPast
        activeAddQuadrant = id
        activeAddDraft = ""
    }

    func updateActiveAddDraft(_ text: String, for id: QuadrantID) {
        guard activeAddQuadrant == id else { return }
        activeAddDraft = text
    }

    func commitActiveAdd(for id: QuadrantID, text inputText: String? = nil, keepAdding: Bool) -> Bool {
        guard activeAddQuadrant == id else { return false }

        let rawText = inputText ?? activeAddDraft
        activeAddDraft = rawText

        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dismissActiveAdd(if: id)
            return false
        }

        addTodo(text: trimmed, to: id)

        if keepAdding {
            suppressBlankAddUntil = .distantPast
            activeAddQuadrant = id
            activeAddDraft = ""
        } else {
            dismissActiveAdd(if: id)
        }

        return true
    }

    func finishActiveAdd(text inputText: String? = nil, for id: QuadrantID? = nil) {
        guard let activeID = activeAddQuadrant else { return }
        guard id == nil || id == activeID else { return }
        _ = commitActiveAdd(for: activeID, text: inputText, keepAdding: false)
    }

    func dismissActiveAdd(if id: QuadrantID? = nil) {
        guard id == nil || activeAddQuadrant == id else { return }
        activeAddQuadrant = nil
        activeAddDraft = ""
        suppressBlankAddUntil = Date().addingTimeInterval(0.2)
    }

    func setSplit(x: Double? = nil, y: Double? = nil) {
        if let x {
            board.splitX = min(max(x, 0.18), 0.82)
        }
        if let y {
            board.splitY = min(max(y, 0.18), 0.82)
        }
    }

    func centerSplit() {
        setSplit(x: 0.5, y: 0.5)
    }

    func updateEmoji(_ emoji: String, for id: QuadrantID) {
        updateQuadrant(id) { quadrant in
            quadrant.emoji = emoji
        }
    }

    func addTodo(text: String, to id: QuadrantID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateQuadrant(id) { quadrant in
            quadrant.todos.append(Todo(text: trimmed))
        }
    }

    func updateTodo(_ todoID: UUID, text: String? = nil, done: Bool? = nil, due: String? = nil, note: String? = nil) {
        for index in board.quadrants.indices {
            guard let todoIndex = board.quadrants[index].todos.firstIndex(where: { $0.id == todoID }) else {
                continue
            }

            if let text {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    board.quadrants[index].todos.remove(at: todoIndex)
                    return
                }
                board.quadrants[index].todos[todoIndex].text = trimmed
            }
            if let done {
                board.quadrants[index].todos[todoIndex].done = done
                board.quadrants[index].todos[todoIndex].completedAt = done ? Date() : nil
            }
            if due != nil {
                board.quadrants[index].todos[todoIndex].due = due
            }
            if note != nil {
                let cleaned = note?.trimmingCharacters(in: .whitespacesAndNewlines)
                board.quadrants[index].todos[todoIndex].note = (cleaned?.isEmpty == false) ? cleaned : nil
            }
            if let done {
                moveTodoAfterCompletionChange(todoID, in: index, done: done)
            }
            return
        }
    }

    func toggleTodoDone(_ todoID: UUID) {
        for quadrant in board.quadrants {
            guard let todo = quadrant.todos.first(where: { $0.id == todoID }) else {
                continue
            }
            updateTodo(todoID, done: !todo.done)
            return
        }
    }

    func clearDue(_ todoID: UUID) {
        for index in board.quadrants.indices {
            guard let todoIndex = board.quadrants[index].todos.firstIndex(where: { $0.id == todoID }) else {
                continue
            }
            board.quadrants[index].todos[todoIndex].due = nil
            return
        }
    }

    func clearNote(_ todoID: UUID) {
        for index in board.quadrants.indices {
            guard let todoIndex = board.quadrants[index].todos.firstIndex(where: { $0.id == todoID }) else {
                continue
            }
            board.quadrants[index].todos[todoIndex].note = nil
            return
        }
    }

    func deleteTodo(_ todoID: UUID) {
        for index in board.quadrants.indices {
            let before = board.quadrants[index].todos.count
            board.quadrants[index].todos.removeAll { $0.id == todoID }
            if board.quadrants[index].todos.count != before {
                return
            }
        }
    }

    func moveTodo(_ todoID: UUID, to target: QuadrantID, before targetTodoID: UUID? = nil) {
        if targetTodoID == todoID {
            return
        }

        var moved: Todo?
        var sourceQuadrantIndex: Int?
        var sourceTodoIndex: Int?

        for index in board.quadrants.indices {
            guard let todoIndex = board.quadrants[index].todos.firstIndex(where: { $0.id == todoID }) else {
                continue
            }

            sourceQuadrantIndex = index
            sourceTodoIndex = todoIndex
            moved = board.quadrants[index].todos.remove(at: todoIndex)
            break
        }

        guard let moved else { return }

        guard let targetQuadrantIndex = board.quadrants.firstIndex(where: { $0.id == target }) else { return }

        let targetIndex = targetTodoID.flatMap { targetTodoID in
            board.quadrants[targetQuadrantIndex].todos.firstIndex { $0.id == targetTodoID }
        }
        var insertionIndex = targetIndex ?? board.quadrants[targetQuadrantIndex].todos.count

        if
            sourceQuadrantIndex == targetQuadrantIndex,
            let sourceTodoIndex,
            sourceTodoIndex < insertionIndex
        {
            insertionIndex -= 1
        }

        insertionIndex = min(max(insertionIndex, 0), board.quadrants[targetQuadrantIndex].todos.count)
        board.quadrants[targetQuadrantIndex].todos.insert(moved, at: insertionIndex)
    }

    private func updateQuadrant(_ id: QuadrantID, mutate: (inout Quadrant) -> Void) {
        guard let index = board.quadrants.firstIndex(where: { $0.id == id }) else { return }
        mutate(&board.quadrants[index])
    }

    private func moveTodoAfterCompletionChange(_ todoID: UUID, in quadrantIndex: Int, done: Bool) {
        guard board.quadrants.indices.contains(quadrantIndex) else { return }
        guard let currentIndex = board.quadrants[quadrantIndex].todos.firstIndex(where: { $0.id == todoID }) else { return }

        let todo = board.quadrants[quadrantIndex].todos.remove(at: currentIndex)
        if done {
            let insertionIndex = board.quadrants[quadrantIndex].todos.firstIndex { $0.done }
                ?? board.quadrants[quadrantIndex].todos.count
            board.quadrants[quadrantIndex].todos.insert(todo, at: insertionIndex)
        } else {
            let insertionIndex = board.quadrants[quadrantIndex].todos.firstIndex { $0.done }
                ?? board.quadrants[quadrantIndex].todos.count
            board.quadrants[quadrantIndex].todos.insert(todo, at: insertionIndex)
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(board) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private static func normalized(_ state: BoardState) -> BoardState {
        var normalized = state
        normalized.splitX = min(max(normalized.splitX, 0.18), 0.82)
        normalized.splitY = min(max(normalized.splitY, 0.18), 0.82)

        let existing = Dictionary(uniqueKeysWithValues: normalized.quadrants.map { ($0.id, $0) })
        normalized.quadrants = QuadrantID.allCases.map { existing[$0] ?? Quadrant.default($0) }
        return normalized
    }
}

private enum Palette {
    static let background = Color(red: 1.0, green: 1.0, blue: 0.99)
    static let softBackground = Color(red: 0.968, green: 0.966, blue: 0.952)
    static let hoverBackground = Color(red: 0.92, green: 0.915, blue: 0.895).opacity(0.58)
    static let activeBackground = Color(red: 0.89, green: 0.885, blue: 0.865).opacity(0.68)
    static let text = Color(red: 0.216, green: 0.208, blue: 0.184)
    static let text2 = Color(red: 0.216, green: 0.208, blue: 0.184).opacity(0.66)
    static let text3 = Color(red: 0.216, green: 0.208, blue: 0.184).opacity(0.46)
    static let faint = Color(red: 0.216, green: 0.208, blue: 0.184).opacity(0.28)
    static let border = Color(red: 0.216, green: 0.208, blue: 0.184).opacity(0.10)
    static let strongBorder = Color(red: 0.216, green: 0.208, blue: 0.184).opacity(0.17)
    static let accent = Color(red: 0.137, green: 0.514, blue: 0.887)
    static let accentSoft = Color(red: 0.137, green: 0.514, blue: 0.887).opacity(0.12)
    static let overdue = Color(red: 0.72, green: 0.22, blue: 0.18)
    static let today = Color(red: 0.78, green: 0.42, blue: 0.12)
}

private let emojiPalette = [
    "🔥", "⭐", "👥", "🗑️", "💼", "🎯", "📌", "⚡",
    "✅", "🧠", "💡", "📚", "🛠️", "🌱", "☕", "🎨",
    "📝", "📅", "💬", "🚀", "🧩", "🔔", "🏷️", "🌙",
    "⏰", "📂", "🔒", "💎", "🍅", "🏃", "💤", "❓"
]

struct ContentView: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var windowModeStore: WindowModeStore
    @State private var now = Date()
    @AppStorage("quadrantDesktop.windowOpacity") private var windowOpacity = 1.0

    var body: some View {
        VStack(spacing: 0) {
            TitleBarView(
                now: now,
                windowOpacity: $windowOpacity,
                windowModeStore: windowModeStore
            )
            MatrixView(store: store)
        }
        .frame(minWidth: 680, minHeight: 440)
        .background(Palette.background)
        .background(WindowOpacityBinder(opacity: windowOpacity).frame(width: 0, height: 0))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.24), radius: 30, x: 0, y: 18)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            now = date
        }
    }
}

struct WindowOpacityBinder: NSViewRepresentable {
    let opacity: Double

    func makeNSView(context: Context) -> OpacityView {
        OpacityView()
    }

    func updateNSView(_ nsView: OpacityView, context: Context) {
        nsView.opacity = opacity
    }

    final class OpacityView: NSView {
        var opacity: Double = 1 {
            didSet { applyOpacity() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyOpacity()
        }

        private func applyOpacity() {
            window?.alphaValue = CGFloat(min(max(opacity, 0.35), 1))
        }
    }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.makeKey()
        }

        override func mouseDragged(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

struct TitleBarView: View {
    let now: Date
    @Binding var windowOpacity: Double
    @ObservedObject var windowModeStore: WindowModeStore

    var body: some View {
        ZStack {
            WindowDragArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 14) {
                BrandMark()
                    .padding(.leading, 22)
                    .allowsHitTesting(false)

                Text(AppMetadata.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.text2)
                    .allowsHitTesting(false)

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Text(DateText.formattedDay(now))
                        .foregroundStyle(Palette.text3)
                    Text(DateText.greeting(now))
                        .fontWeight(.medium)
                        .foregroundStyle(Palette.text)
                }
                .font(.system(size: 13))
                .allowsHitTesting(false)

                OpacitySlider(value: $windowOpacity)

                WindowModeToggle(windowModeStore: windowModeStore)
            }
            .padding(.trailing, 16)
        }
        .frame(height: 44)
    }
}

struct WindowModeToggle: View {
    @ObservedObject var windowModeStore: WindowModeStore

    private var isDesktopResident: Bool {
        windowModeStore.mode == .desktopResident
    }

    var body: some View {
        Button {
            windowModeStore.setMode(isDesktopResident ? .normalWindow : .desktopResident)
        } label: {
            HStack(spacing: 8) {
                Text("桌面常驻")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isDesktopResident ? Palette.text2 : Palette.text3)

                Circle()
                    .fill(isDesktopResident ? Palette.accent : Color.clear)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(isDesktopResident ? Palette.accent : Palette.strongBorder, lineWidth: 1.5)
                    )
                    .shadow(color: isDesktopResident ? Palette.accent.opacity(0.25) : .clear, radius: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(Palette.softBackground.opacity(0.65), in: Capsule())
        .help(isDesktopResident ? "关闭桌面常驻模式" : "启用桌面常驻模式")
        .accessibilityLabel("桌面常驻模式")
        .accessibilityValue(isDesktopResident ? "已启用" : "未启用")
    }
}

struct OpacitySlider: View {
    @Binding var value: Double

    private var clampedValue: Binding<Double> {
        Binding(
            get: { min(max(value, 0.35), 1) },
            set: { value = min(max($0, 0.35), 1) }
        )
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.text3)
                .frame(width: 14)

            Slider(value: clampedValue, in: 0.35...1)
                .controlSize(.small)
                .frame(width: 92)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Palette.softBackground.opacity(0.65), in: Capsule())
        .help("调整页面透明度")
    }
}

struct BrandMark: View {
    var body: some View {
        Grid(horizontalSpacing: 1.5, verticalSpacing: 1.5) {
            GridRow {
                tile(Color(red: 0.91, green: 0.45, blue: 0.42))
                tile(Color(red: 0.91, green: 0.71, blue: 0.42))
            }
            GridRow {
                tile(Color(red: 0.52, green: 0.64, blue: 0.77))
                tile(Color(red: 0.73, green: 0.71, blue: 0.68))
            }
        }
        .frame(width: 14, height: 14)
    }

    private func tile(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(color)
            .frame(width: 6.25, height: 6.25)
    }
}

struct MatrixView: View {
    @ObservedObject var store: BoardStore

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let x = width * store.board.splitX
            let y = height * store.board.splitY
            let rightWidth = max(width - x - 1, 1)
            let bottomHeight = max(height - y - 1, 1)

            ZStack(alignment: .topLeading) {
                VStack(spacing: 1) {
                    HStack(spacing: 1) {
                        QuadrantView(store: store, id: .q1)
                            .frame(width: x, height: y)
                        QuadrantView(store: store, id: .q2)
                            .frame(width: rightWidth, height: y)
                    }
                    HStack(spacing: 1) {
                        QuadrantView(store: store, id: .q3)
                            .frame(width: x, height: bottomHeight)
                        QuadrantView(store: store, id: .q4)
                            .frame(width: rightWidth, height: bottomHeight)
                    }
                }

                Rectangle()
                    .fill(Palette.border)
                    .frame(width: 1, height: height)
                    .position(x: x + 0.5, y: height / 2)

                Rectangle()
                    .fill(Palette.border)
                    .frame(width: width, height: 1)
                    .position(x: width / 2, y: y + 0.5)

                CrossHandle()
                    .position(x: x + 0.5, y: y + 0.5)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 3, coordinateSpace: .named("matrix"))
                            .onChanged { value in
                                store.setSplit(
                                    x: Double(value.location.x / width),
                                    y: Double(value.location.y / height)
                                )
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeOut(duration: 0.18)) {
                            store.centerSplit()
                        }
                    }
            }
            .coordinateSpace(name: "matrix")
        }
    }
}

struct CrossHandle: View {
    @State private var hovering = false

    var body: some View {
        ZStack {
            Circle()
                .fill(hovering ? Palette.accent : Palette.text3)
                .frame(width: hovering ? 8 : 6, height: hovering ? 8 : 6)
                .overlay(
                    Circle()
                        .stroke(hovering ? Palette.accent.opacity(0.25) : Color.clear, lineWidth: 6)
                )
                .shadow(color: hovering ? Palette.accent.opacity(0.22) : .clear, radius: 5)
        }
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
        .cursor(.openHand)
        .onHover { hovering = $0 }
    }
}

struct QuadrantView: View {
    @ObservedObject var store: BoardStore
    let id: QuadrantID

    @State private var addFocusSerial = 0
    @State private var isDropTargeted = false
    @State private var earlierCompletedExpanded = false

    private var quadrant: Quadrant {
        store.quadrant(id)
    }

    private var adding: Bool {
        store.activeAddQuadrant == id
    }

    private var activeAddDraft: Binding<String> {
        Binding(
            get: { store.activeAddQuadrant == id ? store.activeAddDraft : "" },
            set: { store.updateActiveAddDraft($0, for: id) }
        )
    }

    private var activeTodos: [Todo] {
        quadrant.todos.filter { !$0.done }
    }

    private var todayCompletedTodos: [Todo] {
        quadrant.todos.filter { todo in
            guard todo.done, let completedAt = todo.completedAt else { return false }
            return Calendar.current.isDateInToday(completedAt)
        }
        .sorted { lhs, rhs in
            let lhsDate = lhs.completedAt ?? .distantPast
            let rhsDate = rhs.completedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private var earlierCompletedTodos: [Todo] {
        quadrant.todos.filter { todo in
            guard todo.done else { return false }
            guard let completedAt = todo.completedAt else { return true }
            return !Calendar.current.isDateInToday(completedAt)
        }
        .sorted { lhs, rhs in
            let lhsDate = lhs.completedAt ?? .distantPast
            let rhsDate = rhs.completedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            GeometryReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(activeTodos) { todo in
                            todoRow(todo)
                        }

                        if adding {
                            NewTodoRow(
                                text: activeAddDraft,
                                focusSerial: addFocusSerial,
                                onCommit: { inputText, keepAdding in
                                    commitDraft(inputText, keepAdding: keepAdding)
                                },
                                onCancel: cancelDraft,
                                onBlur: finishDraftFromBlur
                            )
                        }

                        ForEach(todayCompletedTodos) { todo in
                            todoRow(todo)
                        }

                        if !earlierCompletedTodos.isEmpty {
                            CompletedSectionHeader(
                                title: "以前已完成",
                                count: earlierCompletedTodos.count,
                                expanded: earlierCompletedExpanded
                            ) {
                                withAnimation(.easeOut(duration: 0.16)) {
                                    earlierCompletedExpanded.toggle()
                                }
                            }

                            if earlierCompletedExpanded {
                                ForEach(earlierCompletedTodos) { todo in
                                    todoRow(todo)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, minHeight: scrollProxy.size.height, alignment: .topLeading)
                    .background(
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                handleBlankAreaTap()
                            }
                    )
                }
            }
        }
        .background(isDropTargeted ? Palette.accentSoft : Palette.background)
        .overlay(
            Rectangle()
                .stroke(store.flashQuadrant == id ? Palette.accentSoft : .clear, lineWidth: 3)
        )
        .animation(.easeOut(duration: 0.16), value: isDropTargeted)
        .animation(.easeOut(duration: 0.18), value: store.flashQuadrant)
        .onDrop(
            of: [.text],
            delegate: TodoDropDelegate(
                store: store,
                targetQuadrant: id,
                targetTodoID: nil,
                isTargeted: $isDropTargeted
            )
        )
        .onChange(of: store.addRequestSerial) { _ in
            guard store.addTarget == id else { return }
            beginAdding()
        }
    }

    private func todoRow(_ todo: Todo) -> some View {
        TodoRow(store: store, todoID: todo.id, onReturn: beginAdding)
            .onDrop(
                of: [.text],
                delegate: TodoDropDelegate(
                    store: store,
                    targetQuadrant: id,
                    targetTodoID: todo.id,
                    isTargeted: $isDropTargeted
                )
            )
    }

    private var header: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(emojiPalette, id: \.self) { emoji in
                    Button(emoji) {
                        store.updateEmoji(emoji, for: id)
                    }
                }
            } label: {
                Text(quadrant.emoji)
                    .font(.system(size: 18))
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(quadrant.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.text)

                    Text("· \(quadrant.subtitle)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.text3)
                }
            }

            Spacer(minLength: 8)
        }
        .padding(.top, 18)
        .padding(.horizontal, 22)
        .padding(.bottom, 10)
    }

    private func commitDraft(_ inputText: String, keepAdding: Bool) {
        let didCommit = store.commitActiveAdd(for: id, text: inputText, keepAdding: keepAdding)
        if didCommit, keepAdding {
            addFocusSerial += 1
        }
    }

    private func finishDraftFromBlur(_ inputText: String, fieldFocusSerial: Int) {
        guard fieldFocusSerial == addFocusSerial else { return }
        store.finishActiveAdd(text: inputText, for: id)
    }

    private func cancelDraft() {
        store.dismissActiveAdd(if: id)
    }

    private func handleBlankAreaTap() {
        if store.activeAddQuadrant != nil {
            NSApp.keyWindow?.makeFirstResponder(NSApp.keyWindow?.contentView)
            DispatchQueue.main.async {
                store.finishActiveAdd()
            }
            return
        }

        guard store.beginAddFromBlankTap(to: id) else { return }
        addFocusSerial += 1
    }

    private func beginAdding() {
        store.activateAdd(to: id)
        addFocusSerial += 1
    }

    fileprivate static func uuid(from item: NSSecureCoding?) -> UUID? {
        if let string = item as? String {
            return UUID(uuidString: string)
        }
        if let data = item as? Data, let string = String(data: data, encoding: .utf8) {
            return UUID(uuidString: string)
        }
        if let attributed = item as? NSAttributedString {
            return UUID(uuidString: attributed.string)
        }
        return nil
    }
}

struct TodoDropDelegate: DropDelegate {
    let store: BoardStore
    let targetQuadrant: QuadrantID
    let targetTodoID: UUID?
    let isTargeted: Binding<Bool>

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func dropEntered(info: DropInfo) {
        isTargeted.wrappedValue = true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        isTargeted.wrappedValue = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted.wrappedValue = false
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            guard let uuid = QuadrantView.uuid(from: item) else { return }
            Task { @MainActor in
                store.moveTodo(uuid, to: targetQuadrant, before: targetTodoID)
            }
        }
        return true
    }
}

struct NewTodoRow: View {
    @Binding var text: String
    let focusSerial: Int
    let onCommit: (_ text: String, _ keepAdding: Bool) -> Void
    let onCancel: () -> Void
    let onBlur: (_ text: String, _ focusSerial: Int) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            Color.clear
                .frame(width: 14, height: 20)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(Palette.strongBorder.opacity(0.65), lineWidth: 1.5)
                .frame(width: 16, height: 16)

            TodoInputField(
                text: $text,
                placeholder: "写下要做的事...",
                focusSerial: focusSerial,
                onCommit: { inputText in onCommit(inputText, true) },
                onCancel: onCancel,
                onBlur: onBlur
            )
            .frame(height: 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 26)
        .padding(.vertical, 3)
        .padding(.leading, 2)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(Palette.hoverBackground, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

struct TodoInputField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let focusSerial: Int
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    let onBlur: (String, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.delegate = context.coordinator
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 13.5)
        textField.textColor = NSColor.labelColor
        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 13.5)
            ]
        )
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        nsView.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 13.5)
            ]
        )

        let currentEditorHasMarkedText = (nsView.currentEditor() as? NSTextView)?.hasMarkedText() == true
        if nsView.stringValue != text, !currentEditorHasMarkedText {
            nsView.stringValue = text
        }

        if context.coordinator.lastFocusSerial != focusSerial {
            context.coordinator.lastFocusSerial = focusSerial
            let coordinator = context.coordinator
            let requestedFocusSerial = focusSerial
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
                coordinator.editingFocusSerial = requestedFocusSerial
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TodoInputField
        var lastFocusSerial = -1
        var editingFocusSerial: Int?
        private var suppressImmediateEndEditing = false

        init(_ parent: TodoInputField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            parent.text = textField.stringValue
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            editingFocusSerial = parent.focusSerial
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            let endedFocusSerial = editingFocusSerial ?? parent.focusSerial
            editingFocusSerial = nil
            if suppressImmediateEndEditing {
                suppressImmediateEndEditing = false
                return
            }
            parent.text = textField.stringValue
            parent.onBlur(textField.stringValue, endedFocusSerial)
        }

        private func suppressEndEditingForCurrentEventCycle() {
            suppressImmediateEndEditing = true
            DispatchQueue.main.async { [weak self] in
                self?.suppressImmediateEndEditing = false
            }
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if textView.hasMarkedText() {
                    return false
                }
                parent.text = textView.string
                suppressEndEditingForCurrentEventCycle()
                parent.onCommit(textView.string)
                return true
            }

            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                suppressEndEditingForCurrentEventCycle()
                parent.onCancel()
                return true
            }

            return false
        }
    }
}

struct CompletedSectionHeader: View {
    let title: String
    let count: Int
    let expanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 14, height: 20)

                Text("\(title) \(count)")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Palette.text3)

                Spacer()
            }
            .padding(.vertical, 5)
            .padding(.leading, 2)
            .padding(.trailing, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle())
        .padding(.top, 6)
    }
}

struct TodoRow: View {
    @ObservedObject var store: BoardStore
    let todoID: UUID
    let onReturn: () -> Void

    @State private var hovering = false

    var body: some View {
        if let todo = store.todo(todoID) {
            row(todo)
        }
    }

    private func row(_ todo: Todo) -> some View {
        HStack(alignment: .center, spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Palette.faint)
                .frame(width: 14, height: 20)
                .opacity(hovering ? 1 : 0)

            Button {
                store.toggleTodoDone(todo.id)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(todo.done ? Palette.accent : Palette.background)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(todo.done ? Palette.accent : Palette.strongBorder, lineWidth: 1.5)
                        )

                    if todo.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.white)
                    }
                }
                .frame(width: 16, height: 16)
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())
            }
                .buttonStyle(.plain)

            TextField("", text: Binding(
                get: { store.todo(todoID)?.text ?? "" },
                set: { store.updateTodo(todoID, text: $0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .foregroundStyle(todo.done ? Palette.faint : Palette.text)
            .strikethrough(todo.done, color: Palette.faint)
            .frame(height: 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onSubmit {
                onReturn()
            }
        }
        .frame(minHeight: 26)
        .padding(.vertical, 3)
        .padding(.leading, 2)
        .padding(.trailing, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(hovering ? Palette.hoverBackground : Color.clear, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .onHover { hovering = $0 }
        .onDrag {
            NSItemProvider(object: todo.id.uuidString as NSString)
        }
    }
}

struct NoteEditor: View {
    @ObservedObject var store: BoardStore
    let todo: Todo

    var body: some View {
        TextEditor(text: Binding(
            get: { todo.note ?? "" },
            set: { store.updateTodo(todo.id, note: $0) }
        ))
        .font(.system(size: 12.5))
        .foregroundStyle(Palette.text2)
        .frame(minHeight: 48, maxHeight: 96)
        .scrollContentBackground(.hidden)
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Palette.softBackground, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Palette.strongBorder)
                .frame(width: 2)
        }
    }
}

struct DuePickerView: View {
    @ObservedObject var store: BoardStore
    let todo: Todo
    @State private var pickedDate: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            DueRow(title: "今天", hint: "Today") {
                store.updateTodo(todo.id, due: DateText.iso(from: Date()))
            }
            DueRow(title: "明天", hint: "Tomorrow") {
                store.updateTodo(todo.id, due: DateText.isoFromOffset(1))
            }
            DueRow(title: "下周", hint: "+7d") {
                store.updateTodo(todo.id, due: DateText.isoFromOffset(7))
            }

            DatePicker("", selection: Binding(
                get: {
                    DateText.date(from: todo.due) ?? pickedDate
                },
                set: { date in
                    pickedDate = date
                    store.updateTodo(todo.id, due: DateText.iso(from: date))
                }
            ), displayedComponents: .date)
            .datePickerStyle(.compact)
            .labelsHidden()
            .padding(.horizontal, 6)
            .padding(.vertical, 4)

            if todo.due != nil {
                Button {
                    store.clearDue(todo.id)
                } label: {
                    Text("清除日期")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.overdue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverButtonStyle())
            }
        }
        .padding(8)
        .frame(width: 220)
        .onAppear {
            pickedDate = DateText.date(from: todo.due) ?? Date()
        }
    }
}

struct DueRow: View {
    let title: String
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.text)
                Spacer()
                Text(hint)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.faint)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle())
    }
}

struct DueChip: View {
    let due: String
    let action: () -> Void

    var body: some View {
        let state = DateText.dueState(due)
        Chip(
            icon: "calendar",
            text: DateText.dueLabel(due),
            foreground: state.foreground,
            background: state.background,
            action: action
        )
    }
}

struct Chip: View {
    let icon: String
    let text: String
    var foreground: Color = Palette.text2
    var background: Color = Palette.softBackground
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(text)
                    .font(.system(size: 11))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(background, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct IconButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12))
                .foregroundStyle(Palette.text3)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverButtonStyle())
    }
}

struct HoverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverButton(configuration: configuration)
    }

    private struct HoverButton: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(configuration.isPressed ? Palette.activeBackground : (hovering ? Palette.hoverBackground : Color.clear))
                )
                .onHover { hovering = $0 }
        }
    }
}

struct CursorModifier: ViewModifier {
    let cursor: NSCursor
    @State private var isInside = false

    func body(content: Content) -> some View {
        content.onHover { inside in
            if inside, !isInside {
                cursor.push()
                isInside = true
            } else if !inside, isInside {
                NSCursor.pop()
                isInside = false
            }
        }
    }
}

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        modifier(CursorModifier(cursor: cursor))
    }
}

enum DateText {
    static func greeting(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 0..<5:
            return "夜深了"
        case 5..<11:
            return "早上好"
        case 11..<13:
            return "中午好"
        case 13..<18:
            return "下午好"
        case 18..<22:
            return "晚上好"
        default:
            return "夜深了"
        }
    }

    static func formattedDay(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.month, .day, .weekday], from: date)
        let week = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = components.weekday.flatMap { week[safe: $0 - 1] } ?? ""
        return "\(components.month ?? 1)月\(components.day ?? 1)日 · \(weekday)"
    }

    static func isoFromOffset(_ days: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return iso(from: date)
    }

    static func iso(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 2000,
            components.month ?? 1,
            components.day ?? 1
        )
    }

    static func date(from iso: String?) -> Date? {
        guard let iso else { return nil }
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func dueLabel(_ iso: String) -> String {
        guard let dueDate = date(from: iso) else { return iso }
        let today = Calendar.current.startOfDay(for: Date())
        let dueDay = Calendar.current.startOfDay(for: dueDate)
        let diff = Calendar.current.dateComponents([.day], from: today, to: dueDay).day ?? 0

        if diff == 0 { return "今天" }
        if diff == 1 { return "明天" }
        if diff == -1 { return "昨天" }
        if diff > 1 && diff < 7 { return "\(diff) 天后" }

        let components = Calendar.current.dateComponents([.month, .day], from: dueDate)
        return "\(components.month ?? 1)/\(components.day ?? 1)"
    }

    static func dueState(_ iso: String) -> (foreground: Color, background: Color) {
        guard let dueDate = date(from: iso) else {
            return (Palette.text2, Palette.softBackground)
        }

        let today = Calendar.current.startOfDay(for: Date())
        let dueDay = Calendar.current.startOfDay(for: dueDate)
        let diff = Calendar.current.dateComponents([.day], from: today, to: dueDay).day ?? 0

        if diff < 0 {
            return (Palette.overdue, Palette.overdue.opacity(0.12))
        }
        if diff == 0 {
            return (Palette.today, Palette.today.opacity(0.12))
        }
        return (Palette.text2, Palette.softBackground)
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

enum StatusIcon {
    static func makeImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let colors = [
                NSColor(red: 0.91, green: 0.45, blue: 0.42, alpha: 1),
                NSColor(red: 0.91, green: 0.71, blue: 0.42, alpha: 1),
                NSColor(red: 0.52, green: 0.64, blue: 0.77, alpha: 1),
                NSColor(red: 0.73, green: 0.71, blue: 0.68, alpha: 1)
            ]

            let tileSize: CGFloat = 7
            let gap: CGFloat = 1.6
            let startX = rect.midX - tileSize - gap / 2
            let startY = rect.midY - tileSize - gap / 2

            for row in 0..<2 {
                for column in 0..<2 {
                    let index = row * 2 + column
                    colors[index].setFill()
                    let tileRect = NSRect(
                        x: startX + CGFloat(column) * (tileSize + gap),
                        y: startY + CGFloat(1 - row) * (tileSize + gap),
                        width: tileSize,
                        height: tileSize
                    )
                    NSBezierPath(roundedRect: tileRect, xRadius: 1.6, yRadius: 1.6).fill()
                }
            }

            return true
        }
        image.isTemplate = false
        return image
    }
}
