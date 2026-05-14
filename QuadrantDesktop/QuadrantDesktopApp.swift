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
    private let themeStore = ThemePreferenceStore()
    private var windowController: DesktopWindowController?
    private var hotKeyManager: QuadrantHotKeyManager?
    private var aboutWindowController: AboutWindowController?
    private var shortcutSettingsWindowController: ShortcutSettingsWindowController?
    private var historyWindowController: HistoryWindowController?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var windowModeCancellable: AnyCancellable?
    private var shortcutChangeCancellable: AnyCancellable?
    private var themeCancellable: AnyCancellable?
    private var appDesktopModeItem: NSMenuItem?
    private var appNormalModeItem: NSMenuItem?
    private var statusShowWindowItem: NSMenuItem?
    private var statusDesktopResidentItem: NSMenuItem?
    private var themeSystemItem: NSMenuItem?
    private var themeLightItem: NSMenuItem?
    private var themeDarkItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureApplicationMenu()

        let controller = DesktopWindowController(
            store: store,
            windowModeStore: windowModeStore,
            themeStore: themeStore,
            openHistory: { [weak self] in
                self?.showHistoryWindow()
            }
        )
        windowController = controller
        controller.showForCurrentMode()

        configureStatusItem()
        observeWindowMode()
        observeShortcuts()
        observeTheme()
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
        menu.showsStateColumn = true

        let showWindowItem = makeStatusActionItem(title: "前台/桌面切换", action: #selector(toggleForegroundDesktopLayerFromMenu))
        let desktopResidentItem = makeStatusActionItem(title: "桌面常驻", action: #selector(toggleDesktopResidentFromStatusMenu))
        desktopResidentItem.onStateImage = Self.statusMenuSmallCheckmarkImage()
        statusShowWindowItem = showWindowItem
        statusDesktopResidentItem = desktopResidentItem
        menu.addItem(showWindowItem)
        menu.addItem(makeStatusActionItem(title: "隐藏窗口", action: #selector(hideWindowFromMenu)))
        menu.addItem(desktopResidentItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeThemeSubmenuItem())
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeStatusActionItem(title: "快捷键设置…", action: #selector(showShortcutSettingsFromMenu)))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(makeStatusActionItem(title: "关于 \(AppMetadata.name)", action: #selector(showAboutFromMenu)))
        let quitItem = makeStatusActionItem(title: "退出", action: #selector(terminateFromStatusMenu))
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = .command
        menu.addItem(quitItem)
        updateStatusShowWindowShortcut()
        updateModeMenuItems()
        updateThemeMenuItems()
        return menu
    }

    private func makeStatusActionItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = nil
        item.state = .off
        return item
    }

    private static func statusMenuSmallCheckmarkImage() -> NSImage? {
        guard let image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "已启用") else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 9, height: 9)
        return image
    }

    private func makeThemeSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "外观", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: "外观")
        submenu.showsStateColumn = true

        let systemItem = makeThemeMenuItem(for: .system)
        let lightItem = makeThemeMenuItem(for: .light)
        let darkItem = makeThemeMenuItem(for: .dark)
        themeSystemItem = systemItem
        themeLightItem = lightItem
        themeDarkItem = darkItem

        submenu.addItem(systemItem)
        submenu.addItem(lightItem)
        submenu.addItem(darkItem)
        item.submenu = submenu
        return item
    }

    private func makeThemeMenuItem(for preference: AppThemePreference) -> NSMenuItem {
        let selector: Selector
        switch preference {
        case .system:
            selector = #selector(selectSystemThemeFromMenu)
        case .light:
            selector = #selector(selectLightThemeFromMenu)
        case .dark:
            selector = #selector(selectDarkThemeFromMenu)
        }

        let item = NSMenuItem(title: preference.title, action: selector, keyEquivalent: "")
        item.target = self
        item.representedObject = preference.rawValue
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
        statusDesktopResidentItem?.image = nil
        statusDesktopResidentItem?.state = mode == .desktopResident ? .on : .off
    }

    private func observeShortcuts() {
        shortcutChangeCancellable = NotificationCenter.default
            .publisher(for: .quadrantDesktopShortcutsDidChange)
            .sink { [weak self] _ in
                self?.updateStatusShowWindowShortcut()
            }
    }

    private func observeTheme() {
        themeCancellable = themeStore.$preference.sink { [weak self] _ in
            self?.updateThemeMenuItems()
            self?.applyThemeToOpenWindows()
        }
    }

    private func updateThemeMenuItems() {
        let preference = themeStore.preference
        themeSystemItem?.state = preference == .system ? .on : .off
        themeLightItem?.state = preference == .light ? .on : .off
        themeDarkItem?.state = preference == .dark ? .on : .off
    }

    private func applyThemeToOpenWindows() {
        themeStore.applyAppearance()
        let appearance = themeStore.nsAppearance
        for window in NSApp.windows {
            window.appearance = appearance
            window.contentView?.needsDisplay = true
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
                self?.windowController?.toggleForegroundDesktopLayer()
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

    @objc private func selectSystemThemeFromMenu() {
        selectThemeFromMenu(.system)
    }

    @objc private func selectLightThemeFromMenu() {
        selectThemeFromMenu(.light)
    }

    @objc private func selectDarkThemeFromMenu() {
        selectThemeFromMenu(.dark)
    }

    private func selectThemeFromMenu(_ preference: AppThemePreference) {
        statusMenu?.cancelTracking()
        themeStore.setPreference(preference)
        updateThemeMenuItems()
        applyThemeToOpenWindows()
    }

    @objc private func statusItemClicked() {
        updateModeMenuItems()
        updateThemeMenuItems()

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

    @objc private func toggleForegroundDesktopLayerFromMenu() {
        statusMenu?.cancelTracking()

        DispatchQueue.main.async { [weak self] in
            self?.windowController?.toggleForegroundDesktopLayer()
        }
    }

    @objc private func toggleDesktopResidentFromStatusMenu() {
        statusMenu?.cancelTracking()

        let nextMode: WindowDisplayMode = windowModeStore.mode == .desktopResident ? .normalWindow : .desktopResident
        windowModeStore.setMode(nextMode)
        updateModeMenuItems()

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
                aboutWindowController = AboutWindowController(themeStore: themeStore)
            }
            aboutWindowController?.show()
        }
    }

    @objc private func showShortcutSettingsFromMenu() {
        statusMenu?.cancelTracking()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            if shortcutSettingsWindowController == nil {
                shortcutSettingsWindowController = ShortcutSettingsWindowController(themeStore: themeStore)
            }
            shortcutSettingsWindowController?.show()
        }
    }

    private func showHistoryWindow() {
        if historyWindowController == nil {
            historyWindowController = HistoryWindowController(store: store, themeStore: themeStore)
        }
        historyWindowController?.show()
    }
}

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class FocusSinkHostingView<Content: View>: NSHostingView<Content> {
    var onMouseDown: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?()
        super.mouseDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        onMouseDown?()
        super.rightMouseDown(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        onMouseDown?()
        super.otherMouseDown(with: event)
    }
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

enum AppThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "跟随 macOS"
        case .light:
            return "明亮"
        case .dark:
            return "黑暗"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    var appearanceName: NSAppearance.Name? {
        switch self {
        case .system:
            return nil
        case .light:
            return .aqua
        case .dark:
            return .darkAqua
        }
    }
}

@MainActor
final class ThemePreferenceStore: ObservableObject {
    private static let defaultsKey = "quadrantDesktop.themePreference"

    @Published private(set) var preference: AppThemePreference {
        didSet {
            UserDefaults.standard.set(preference.rawValue, forKey: Self.defaultsKey)
            applyAppearance()
        }
    }

    init() {
        if
            let rawValue = UserDefaults.standard.string(forKey: Self.defaultsKey),
            let preference = AppThemePreference(rawValue: rawValue)
        {
            self.preference = preference
        } else {
            preference = .system
        }
        applyAppearance()
    }

    func setPreference(_ preference: AppThemePreference) {
        guard self.preference != preference else {
            objectWillChange.send()
            applyAppearance()
            return
        }
        self.preference = preference
    }

    var nsAppearance: NSAppearance? {
        preference.appearanceName.flatMap { NSAppearance(named: $0) }
    }

    func applyAppearance() {
        NSApp.appearance = nsAppearance
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
    private static let frameAutosaveName = "QuadrantDesktopWindowFrame.v3"
    private static let minimumWindowSize = NSSize(width: 760, height: 560)
    private static let defaultWindowSize = NSSize(width: 760, height: 720)
    private let store: BoardStore
    private let windowModeStore: WindowModeStore
    private let themeStore: ThemePreferenceStore
    private var settleTask: Task<Void, Never>?
    private var windowModeCancellable: AnyCancellable?
    private var isParkedOnDesktopLayer = false

    init(
        store: BoardStore,
        windowModeStore: WindowModeStore,
        themeStore: ThemePreferenceStore,
        openHistory: @escaping () -> Void
    ) {
        self.store = store
        self.windowModeStore = windowModeStore
        self.themeStore = themeStore

        let initialFrame = Self.defaultFrame()
        let window = DesktopWindow(
            contentRect: initialFrame,
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )

        window.title = ""
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.minSize = Self.minimumWindowSize
        window.setFrameAutosaveName(Self.frameAutosaveName)

        super.init(window: window)

        let rootView = ContentView(
            store: store,
            themeStore: themeStore,
            openHistory: openHistory,
            prepareForInterfaceInteraction: { [weak self] in
                self?.prepareForInterfaceInteraction()
            },
            returnToDesktopLayer: { [weak self] in
                self?.returnToDesktopLayer()
            }
        )
        let hostingView = FocusSinkHostingView(rootView: rootView)
        hostingView.onMouseDown = { [weak self] in
            self?.prepareForInterfaceInteraction()
        }
        window.contentView = hostingView
        window.initialFirstResponder = hostingView
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

    func toggleForegroundDesktopLayer() {
        guard let window, window.isVisible else {
            showForCurrentMode()
            return
        }

        if isParkedOnDesktopLayer {
            showForCurrentMode()
            return
        }

        if NSApp.isActive {
            returnToDesktopLayer()
        } else {
            showForCurrentMode()
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

    func returnToDesktopLayer() {
        settleTask?.cancel()

        DispatchQueue.main.async { [weak self] in
            self?.parkOnDesktopLayer()
        }
    }

    private func prepareForInterfaceInteraction() {
        switch windowModeStore.mode {
        case .desktopResident:
            raiseForEditing()
        case .normalWindow:
            if isParkedOnDesktopLayer {
                showNormalWindow()
            }
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        switch windowModeStore.mode {
        case .desktopResident:
            raiseForEditing(activateApp: false)
        case .normalWindow:
            if isParkedOnDesktopLayer {
                showNormalWindow(activateApp: false)
            } else {
                applyNormalWindowBehavior()
            }
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
        isParkedOnDesktopLayer = false
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
        isParkedOnDesktopLayer = false
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
        parkOnDesktopLayer()
    }

    private func parkOnDesktopLayer() {
        applyDesktopResidentWindowBehavior()
        guard let window else { return }

        isParkedOnDesktopLayer = true
        let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
        window.level = NSWindow.Level(rawValue: desktopIconLevel + 1)
        window.orderFrontRegardless()
    }

    private static func defaultFrame() -> NSRect {
        let visibleFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let maxWidth = visibleFrame.width * 0.72
        let maxHeight = visibleFrame.height * 0.78
        let width = max(minimumWindowSize.width, min(defaultWindowSize.width, maxWidth))
        let height = max(minimumWindowSize.height, min(defaultWindowSize.height, maxHeight))

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
    var createdAt: Date?
    var completedAt: Date?
    var due: String?
    var note: String?

    init(
        id: UUID = UUID(),
        text: String,
        done: Bool = false,
        createdAt: Date? = Date(),
        completedAt: Date? = nil,
        due: String? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.text = text
        self.done = done
        self.createdAt = createdAt
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

private enum MatrixLayoutLimits {
    static let minQuadrantWidth: CGFloat = 360
    static let minQuadrantHeight: CGFloat = 220
    static let defaultSplitRange: ClosedRange<Double> = 0.18...0.82

    static func splitRange(totalLength: CGFloat, minimumLength: CGFloat) -> ClosedRange<Double> {
        guard totalLength > 0 else { return defaultSplitRange }

        let minimumFraction = Double(min(max(minimumLength / totalLength, 0.18), 0.48))
        return minimumFraction...(1 - minimumFraction)
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

struct DailyBoardSnapshot: Identifiable, Codable, Equatable {
    var dateID: String
    var capturedAt: Date
    var board: BoardState

    var id: String { dateID }
}

private enum SnapshotProjection {
    static func board(_ state: BoardState, for dateID: String) -> BoardState {
        var projected = state
        projected.quadrants = state.quadrants.map { quadrant in
            var projectedQuadrant = quadrant
            projectedQuadrant.todos = visibleTodos(in: quadrant, on: dateID)
            return projectedQuadrant
        }
        return projected
    }

    static func visibleTodos(in quadrant: Quadrant, on dateID: String) -> [Todo] {
        let endOfDay = DateText.endOfDay(for: dateID) ?? Date()

        return quadrant.todos.compactMap { todo in
            visibleTodo(todo, on: dateID, endOfDay: endOfDay)
        }
    }

    private static func visibleTodo(_ todo: Todo, on dateID: String, endOfDay: Date) -> Todo? {
        if let createdAt = todo.createdAt, createdAt > endOfDay {
            return nil
        }

        guard let completedAt = todo.completedAt else {
            return todo.done ? nil : todo
        }

        var projectedTodo = todo

        if completedAt > endOfDay {
            projectedTodo.done = false
            projectedTodo.completedAt = nil
            return projectedTodo
        }

        if DateText.isDate(completedAt, sameDayAs: dateID) {
            projectedTodo.done = true
            projectedTodo.completedAt = completedAt
            return projectedTodo
        }

        return nil
    }
}

private enum DemoSeedFactory {
    static let defaultsVersionKey = "quadrantDesktop.demoSeedVersion"
    static let currentVersion = 1
    static let marker = "myDAY.demo.retailWarm.v1"

    struct Seed {
        let board: BoardState
    }

    private struct DemoTaskSpec {
        let startDay: Int
        let durationDays: Int?
        let quadrant: QuadrantID
        let text: String
    }

    static func make(referenceDate: Date = Date()) -> Seed {
        let calendar = Calendar.current
        let endDay = calendar.startOfDay(for: referenceDate)
        let startDay = calendar.startOfDay(
            for: calendar.date(byAdding: .month, value: -1, to: endDay) ?? endDay
        )
        let days = days(from: startDay, through: endDay)
        let fullBoard = fullBoard(for: days)

        return Seed(board: fullBoard)
    }

    private static func fullBoard(for days: [Date]) -> BoardState {
        var board = BoardState.blank
        board.splitX = 0.5
        board.splitY = 0.5

        board.quadrants = board.quadrants.map { quadrant in
            var quadrant = quadrant
            quadrant.todos = specs.compactMap { spec in
                guard spec.quadrant == quadrant.id else { return nil }
                return todo(from: spec, days: days)
            }
            return quadrant
        }

        return board
    }

    private static func todo(from spec: DemoTaskSpec, days: [Date]) -> Todo? {
        guard !days.isEmpty else { return nil }
        let createdIndex = min(max(spec.startDay, 0), days.count - 1)
        let createdAt = date(on: days[createdIndex], hour: 10 + (createdIndex % 5), minute: (createdIndex * 7) % 50)
        let completionIndex = spec.durationDays.map { createdIndex + $0 }
        let completedAt = completionIndex.flatMap { index -> Date? in
            guard days.indices.contains(index) else { return nil }
            return date(on: days[index], hour: 17 + (index % 3), minute: 20 + (index * 5) % 35)
        }

        return Todo(
            id: UUID(),
            text: spec.text,
            done: completedAt != nil,
            createdAt: createdAt,
            completedAt: completedAt,
            due: nil,
            note: marker
        )
    }

    private static func days(from startDay: Date, through endDay: Date) -> [Date] {
        var days: [Date] = []
        var day = startDay

        while day <= endDay {
            days.append(day)
            guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = nextDay
        }

        return days
    }

    private static func date(on day: Date, hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    private static let specs: [DemoTaskSpec] = [
        DemoTaskSpec(startDay: 0, durationDays: 0, quadrant: .q1, text: "开店前确认第一批预约取机袋"),
        DemoTaskSpec(startDay: 0, durationDays: 1, quadrant: .q2, text: "整理昨天晨会里的顾客故事"),
        DemoTaskSpec(startDay: 1, durationDays: 0, quadrant: .q3, text: "请伙伴补齐儿童桌彩色贴纸"),
        DemoTaskSpec(startDay: 1, durationDays: 2, quadrant: .q4, text: "把抽屉里的备用笔归成一束"),
        DemoTaskSpec(startDay: 2, durationDays: 1, quadrant: .q1, text: "给演示桌补齐清洁布和软布"),
        DemoTaskSpec(startDay: 2, durationDays: 3, quadrant: .q2, text: "为周末摄影散步准备三条示例路线"),
        DemoTaskSpec(startDay: 3, durationDays: 0, quadrant: .q3, text: "请仓库同事确认表带颜色库存"),
        DemoTaskSpec(startDay: 4, durationDays: 1, quadrant: .q2, text: "挑一张适合课堂开场的照片"),
        DemoTaskSpec(startDay: 4, durationDays: 0, quadrant: .q1, text: "检查儿童场次 iPad 的电量"),
        DemoTaskSpec(startDay: 5, durationDays: 2, quadrant: .q4, text: "给白板换一支顺手的笔"),
        DemoTaskSpec(startDay: 5, durationDays: 1, quadrant: .q3, text: "把讲师需要的转接头放到培训桌"),
        DemoTaskSpec(startDay: 6, durationDays: 0, quadrant: .q1, text: "把等候区散开的 MagSafe 配件归位"),
        DemoTaskSpec(startDay: 7, durationDays: 2, quadrant: .q2, text: "给新同事准备一份门店导览"),
        DemoTaskSpec(startDay: 7, durationDays: 0, quadrant: .q3, text: "请伙伴留意午后配件墙的空位"),
        DemoTaskSpec(startDay: 8, durationDays: 1, quadrant: .q1, text: "午后巡店：每台演示机都亮着"),
        DemoTaskSpec(startDay: 9, durationDays: 3, quadrant: .q2, text: "复盘昨天试用台的动线"),
        DemoTaskSpec(startDay: 9, durationDays: 0, quadrant: .q4, text: "把休息区遗落的小票清掉"),
        DemoTaskSpec(startDay: 10, durationDays: 1, quadrant: .q1, text: "确认维修取件顾客的等候提醒"),
        DemoTaskSpec(startDay: 10, durationDays: 2, quadrant: .q3, text: "请伙伴把亲子场小徽章放进抽屉"),
        DemoTaskSpec(startDay: 11, durationDays: 0, quadrant: .q2, text: "更新配件墙上几张温柔的小标签"),
        DemoTaskSpec(startDay: 12, durationDays: 1, quadrant: .q1, text: "开门前再看一遍当天预约名单"),
        DemoTaskSpec(startDay: 12, durationDays: 4, quadrant: .q2, text: "写下三句适合换机顾客的开场问题"),
        DemoTaskSpec(startDay: 13, durationDays: 0, quadrant: .q3, text: "请同事把展示桌的线绕顺"),
        DemoTaskSpec(startDay: 14, durationDays: 2, quadrant: .q4, text: "挑一首轻一点的开店歌单"),
        DemoTaskSpec(startDay: 14, durationDays: 1, quadrant: .q1, text: "给临时加场的课堂预留第一排座位"),
        DemoTaskSpec(startDay: 15, durationDays: 2, quadrant: .q2, text: "把本周最暖的一次顾客反馈记下来"),
        DemoTaskSpec(startDay: 16, durationDays: 0, quadrant: .q1, text: "确认展示机照片墙恢复到春日相册"),
        DemoTaskSpec(startDay: 16, durationDays: 1, quadrant: .q3, text: "请伙伴给取货台补几只纸袋"),
        DemoTaskSpec(startDay: 17, durationDays: 3, quadrant: .q2, text: "准备一页给家长看的屏幕时间提示"),
        DemoTaskSpec(startDay: 18, durationDays: 0, quadrant: .q4, text: "把备用铭牌按名字排好"),
        DemoTaskSpec(startDay: 18, durationDays: 1, quadrant: .q1, text: "跟进那位想给妈妈换机的顾客"),
        DemoTaskSpec(startDay: 19, durationDays: 2, quadrant: .q2, text: "给周末亲子场想一个轻松开场"),
        DemoTaskSpec(startDay: 20, durationDays: 0, quadrant: .q3, text: "请伙伴把摄影路线发到群里"),
        DemoTaskSpec(startDay: 21, durationDays: 1, quadrant: .q1, text: "检查取件柜里今天到店的名字"),
        DemoTaskSpec(startDay: 21, durationDays: 4, quadrant: .q2, text: "整理一份适合新用户的入门提醒"),
        DemoTaskSpec(startDay: 22, durationDays: 0, quadrant: .q4, text: "把员工区的小便签撕掉旧页"),
        DemoTaskSpec(startDay: 23, durationDays: 1, quadrant: .q1, text: "给等候时间较久的顾客递上进度"),
        DemoTaskSpec(startDay: 23, durationDays: 3, quadrant: .q3, text: "请讲师确认投屏线是否够长"),
        DemoTaskSpec(startDay: 24, durationDays: 2, quadrant: .q2, text: "把今天学到的三个顾客用词收好"),
        DemoTaskSpec(startDay: 25, durationDays: 0, quadrant: .q1, text: "确认展示桌边缘没有留下指纹"),
        DemoTaskSpec(startDay: 25, durationDays: nil, quadrant: .q2, text: "慢慢整理下周 Family Setup 提醒卡"),
        DemoTaskSpec(startDay: 26, durationDays: 1, quadrant: .q3, text: "请伙伴把 Today at Apple 座椅排开"),
        DemoTaskSpec(startDay: 27, durationDays: nil, quadrant: .q2, text: "给新同事留一页午后巡店笔记"),
        DemoTaskSpec(startDay: 27, durationDays: 0, quadrant: .q4, text: "把桌角的小贴纸轻轻揭掉"),
        DemoTaskSpec(startDay: 28, durationDays: 1, quadrant: .q1, text: "确认今天取机顾客的欢迎卡"),
        DemoTaskSpec(startDay: 28, durationDays: nil, quadrant: .q2, text: "想一个周末亲子场的开场问题"),
        DemoTaskSpec(startDay: 29, durationDays: nil, quadrant: .q3, text: "请伙伴明早顺手检查耳机试戴区"),
        DemoTaskSpec(startDay: 30, durationDays: nil, quadrant: .q1, text: "开店前给演示机补满电"),
        DemoTaskSpec(startDay: 30, durationDays: nil, quadrant: .q2, text: "把常被问到的换机问题写成一句话"),
        DemoTaskSpec(startDay: 30, durationDays: nil, quadrant: .q4, text: "给自己留五分钟喝口水")
    ]
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
    init(themeStore: ThemePreferenceStore) {
        let hostingController = NSHostingController(rootView: AboutView(themeStore: themeStore))
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
    @ObservedObject var themeStore: ThemePreferenceStore
    @ObservedObject private var updateModel: AboutUpdateViewModel

    @MainActor
    init(themeStore: ThemePreferenceStore) {
        self.themeStore = themeStore
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
        .background(Palette.background)
        .preferredColorScheme(themeStore.preference.colorScheme)
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

    init(themeStore: ThemePreferenceStore) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 328),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "快捷键"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 560, height: 328)
        window.contentView = NSHostingView(
            rootView: ShortcutSettingsView(viewModel: viewModel, themeStore: themeStore)
        )
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
            return "前台/桌面切换"
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
    @ObservedObject var themeStore: ThemePreferenceStore
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
        .frame(width: 560)
        .background(Palette.background)
        .preferredColorScheme(themeStore.preference.colorScheme)
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
                .frame(width: 116, alignment: .leading)

            Text(isRecording ? "按键中…" : shortcut)
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(isRecording ? Palette.accent : Palette.text2)
                .lineLimit(1)
                .frame(width: 176, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Palette.softBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))

            Button("录制", action: onRecord)
                .buttonStyle(.bordered)
                .frame(width: 58)

            Button("清除", action: onClear)
                .buttonStyle(.borderless)
                .frame(width: 50)
                .disabled(clearDisabled)
        }
    }
}

@MainActor
final class BoardStore: ObservableObject {
    private static let defaultsKey = "quadrantDesktop.board.v1"
    private static let historyDefaultsKey = "quadrantDesktop.boardHistory.v1"
    private var flashTask: Task<Void, Never>?
    private var suppressBlankAddUntil = Date.distantPast
    private var historyCacheKey: String?

    @Published var board: BoardState {
        didSet { save() }
    }

    @Published private(set) var historySnapshots: [DailyBoardSnapshot]
    @Published var addTarget: QuadrantID?
    @Published var addRequestSerial = 0
    @Published var flashQuadrant: QuadrantID?
    @Published var activeAddQuadrant: QuadrantID?
    @Published var activeAddDraft = ""

    init() {
        let storedBoardData = UserDefaults.standard.data(forKey: Self.defaultsKey)
        let storedHistoryData = UserDefaults.standard.data(forKey: Self.historyDefaultsKey)
        let demoSeed = (storedBoardData == nil && storedHistoryData == nil)
            ? DemoSeedFactory.make(referenceDate: Date())
            : nil

        let legacyHistory: [DailyBoardSnapshot]? = {
            guard
                let historyData = storedHistoryData,
                let decodedHistory = try? JSONDecoder().decode([DailyBoardSnapshot].self, from: historyData)
            else {
                return nil
            }
            return decodedHistory
        }()

        var initialBoard: BoardState
        if
            let data = storedBoardData,
            let decoded = try? JSONDecoder().decode(BoardState.self, from: data),
            !decoded.quadrants.isEmpty
        {
            initialBoard = Self.normalized(decoded)
        } else if let demoSeed {
            initialBoard = Self.normalized(demoSeed.board)
        } else {
            initialBoard = .blank
        }

        if let legacyHistory {
            initialBoard = Self.boardByMergingLegacyHistory(legacyHistory, into: initialBoard)
        }
        board = initialBoard
        historySnapshots = []

        if demoSeed != nil {
            saveBoardOnly()
            UserDefaults.standard.set(DemoSeedFactory.currentVersion, forKey: DemoSeedFactory.defaultsVersionKey)
        }

        migrateLegacyCompletionDates()
        saveBoardOnly()
        if legacyHistory != nil {
            UserDefaults.standard.removeObject(forKey: Self.historyDefaultsKey)
        }
        refreshDerivedHistoryIfNeeded(force: true)
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

    var earliestSnapshotDateID: String? {
        historySnapshots.first?.dateID
    }

    var latestSnapshotDateID: String? {
        historySnapshots.last?.dateID
    }

    func snapshot(for dateID: String) -> DailyBoardSnapshot? {
        historySnapshots.first { $0.dateID == dateID }
    }

    func hasSnapshot(on dateID: String) -> Bool {
        snapshot(for: dateID) != nil
    }

    func ensureCurrentDaySnapshot(at date: Date = Date()) {
        refreshDerivedHistoryIfNeeded(now: date)
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

    func setSplit(
        x: Double? = nil,
        y: Double? = nil,
        xRange: ClosedRange<Double> = MatrixLayoutLimits.defaultSplitRange,
        yRange: ClosedRange<Double> = MatrixLayoutLimits.defaultSplitRange
    ) {
        if let x {
            board.splitX = MatrixLayoutLimits.clamp(x, to: xRange)
        }
        if let y {
            board.splitY = MatrixLayoutLimits.clamp(y, to: yRange)
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
        saveBoardOnly()
        refreshDerivedHistoryIfNeeded()
    }

    private func saveBoardOnly() {
        guard let data = try? JSONEncoder().encode(board) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }

    private func refreshDerivedHistoryIfNeeded(force: Bool = false, now: Date = Date()) {
        let todayID = DateText.iso(from: now)
        let cacheKey = Self.historyCacheKey(for: board, todayID: todayID)
        guard force || cacheKey != historyCacheKey else { return }

        historySnapshots = Self.derivedHistory(from: board, through: now)
        historyCacheKey = cacheKey
    }

    private static func derivedHistory(from state: BoardState, through now: Date) -> [DailyBoardSnapshot] {
        let normalizedBoard = normalized(state)
        let today = Calendar.current.startOfDay(for: now)
        let todos = normalizedBoard.quadrants.flatMap(\.todos)
        let relevantDates = todos.flatMap { todo -> [Date] in
            [todo.createdAt, todo.completedAt].compactMap { $0 }
        }
        let earliest = relevantDates
            .filter { $0 <= now }
            .map { Calendar.current.startOfDay(for: $0) }
            .min() ?? today

        return historyDays(from: earliest, through: today).map { day in
            let dateID = DateText.iso(from: day)
            let capturedAt = dateID == DateText.iso(from: now)
                ? now
                : (DateText.endOfDay(for: dateID) ?? day)

            return DailyBoardSnapshot(
                dateID: dateID,
                capturedAt: capturedAt,
                board: SnapshotProjection.board(normalizedBoard, for: dateID)
            )
        }
    }

    private static func historyDays(from startDay: Date, through endDay: Date) -> [Date] {
        var days: [Date] = []
        var day = Calendar.current.startOfDay(for: startDay)
        let lastDay = Calendar.current.startOfDay(for: endDay)

        while day <= lastDay {
            days.append(day)
            guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = nextDay
        }

        return days
    }

    private static func historyCacheKey(for state: BoardState, todayID: String) -> String {
        var parts = [todayID]
        for quadrant in state.quadrants {
            parts.append(quadrant.id.rawValue)
            parts.append(quadrant.emoji)
            parts.append(quadrant.title)
            parts.append(quadrant.subtitle)

            for todo in quadrant.todos {
                parts.append(todo.id.uuidString)
                parts.append(todo.text)
                parts.append(todo.done ? "1" : "0")
                parts.append(historyDateToken(todo.createdAt))
                parts.append(historyDateToken(todo.completedAt))
            }
        }
        return parts.joined(separator: "\u{1F}")
    }

    private static func historyDateToken(_ date: Date?) -> String {
        guard let date else { return "-" }
        return String(format: "%.3f", date.timeIntervalSinceReferenceDate)
    }

    private func migrateLegacyCompletionDates() {
        let legacyTodos = board.quadrants
            .flatMap(\.todos)
            .filter { $0.done && $0.completedAt == nil }

        guard
            !legacyTodos.isEmpty,
            let yesterdayDateID = DateText.dateID(byAdding: -1, to: DateText.iso(from: Date()))
        else {
            return
        }

        let completedAt = DateText.endOfDay(for: yesterdayDateID) ?? Date()
        var migratedBoard = board
        var changed = false

        for quadrantIndex in migratedBoard.quadrants.indices {
            for todoIndex in migratedBoard.quadrants[quadrantIndex].todos.indices {
                guard
                    migratedBoard.quadrants[quadrantIndex].todos[todoIndex].done,
                    migratedBoard.quadrants[quadrantIndex].todos[todoIndex].completedAt == nil
                else {
                    continue
                }

                migratedBoard.quadrants[quadrantIndex].todos[todoIndex].completedAt = completedAt
                changed = true
            }
        }

        if changed {
            board = migratedBoard
        }
    }

    private static func normalized(_ state: BoardState) -> BoardState {
        var normalized = state
        normalized.splitX = min(max(normalized.splitX, 0.18), 0.82)
        normalized.splitY = min(max(normalized.splitY, 0.18), 0.82)

        let existing = Dictionary(uniqueKeysWithValues: normalized.quadrants.map { ($0.id, $0) })
        normalized.quadrants = QuadrantID.allCases.map { existing[$0] ?? Quadrant.default($0) }
        return normalized
    }

    private static func boardByMergingLegacyHistory(
        _ snapshots: [DailyBoardSnapshot],
        into board: BoardState
    ) -> BoardState {
        var mergedBoard = normalized(board)
        for snapshot in structurallyNormalizedSnapshots(snapshots) {
            for quadrant in snapshot.board.quadrants {
                guard let quadrantIndex = mergedBoard.quadrants.firstIndex(where: { $0.id == quadrant.id }) else {
                    continue
                }

                for todo in quadrant.todos {
                    mergeLegacyTodo(todo, preferredQuadrantIndex: quadrantIndex, into: &mergedBoard)
                }
            }
        }
        return normalized(mergedBoard)
    }

    private static func mergeLegacyTodo(
        _ legacyTodo: Todo,
        preferredQuadrantIndex: Int,
        into board: inout BoardState
    ) {
        for quadrantIndex in board.quadrants.indices {
            guard let todoIndex = board.quadrants[quadrantIndex].todos.firstIndex(where: { $0.id == legacyTodo.id }) else {
                continue
            }

            var todo = board.quadrants[quadrantIndex].todos[todoIndex]
            if todo.createdAt == nil || (legacyTodo.createdAt != nil && legacyTodo.createdAt! < todo.createdAt!) {
                todo.createdAt = legacyTodo.createdAt
            }
            if todo.completedAt == nil || (legacyTodo.completedAt != nil && legacyTodo.completedAt! < todo.completedAt!) {
                todo.completedAt = legacyTodo.completedAt
                todo.done = true
            }
            if todo.text.isEmpty {
                todo.text = legacyTodo.text
            }
            board.quadrants[quadrantIndex].todos[todoIndex] = todo
            return
        }

        guard board.quadrants.indices.contains(preferredQuadrantIndex) else { return }
        board.quadrants[preferredQuadrantIndex].todos.append(legacyTodo)
    }

    private static func structurallyNormalizedSnapshots(_ snapshots: [DailyBoardSnapshot]) -> [DailyBoardSnapshot] {
        var byDate: [String: DailyBoardSnapshot] = [:]

        for snapshot in snapshots {
            var normalizedSnapshot = snapshot
            normalizedSnapshot.board = normalized(snapshot.board)
            normalizedSnapshot.board = boardByApplyingSnapshotCompletionFallback(
                normalizedSnapshot.board,
                dateID: normalizedSnapshot.dateID
            )
            byDate[snapshot.dateID] = normalizedSnapshot
        }

        return byDate.values.sorted { $0.dateID < $1.dateID }
    }

    private static func boardByApplyingSnapshotCompletionFallback(
        _ state: BoardState,
        dateID: String
    ) -> BoardState {
        let fallbackCompletedAt = DateText.endOfDay(for: dateID)
        var state = state

        state.quadrants = state.quadrants.map { quadrant in
            var quadrant = quadrant
            quadrant.todos = quadrant.todos.map { todo in
                var todo = todo
                if todo.done, todo.completedAt == nil {
                    todo.completedAt = fallbackCompletedAt
                }
                return todo
            }
            return quadrant
        }

        return state
    }
}

private enum Palette {
    static let background = color(
        light: nsColor(1.0, 1.0, 0.99),
        dark: nsColor(0.098, 0.094, 0.086)
    )
    static let softBackground = color(
        light: nsColor(0.968, 0.966, 0.952),
        dark: nsColor(0.150, 0.142, 0.126)
    )
    static let surfaceGlassTint = color(
        light: nsColor(1.0, 1.0, 0.985, 0.34),
        dark: nsColor(0.126, 0.118, 0.104, 0.42)
    )
    static let mainWindowGlassTint = color(
        light: nsColor(1.0, 1.0, 0.985, 0.50),
        dark: nsColor(0.112, 0.106, 0.094, 0.52)
    )
    static let titleBarGlassTint = surfaceGlassTint
    static let quadrantGlassTint = surfaceGlassTint
    static let controlGlassTint = color(
        light: nsColor(1.0, 1.0, 0.985, 0.48),
        dark: nsColor(0.150, 0.140, 0.124, 0.54)
    )
    static let hoverBackground = color(
        light: nsColor(0.92, 0.915, 0.895, 0.58),
        dark: nsColor(0.255, 0.240, 0.210, 0.72)
    )
    static let activeBackground = color(
        light: nsColor(0.89, 0.885, 0.865, 0.68),
        dark: nsColor(0.320, 0.295, 0.250, 0.82)
    )
    static let text = color(
        light: nsColor(0.216, 0.208, 0.184),
        dark: nsColor(0.925, 0.905, 0.860)
    )
    static let text2 = color(
        light: nsColor(0.216, 0.208, 0.184, 0.66),
        dark: nsColor(0.925, 0.905, 0.860, 0.70)
    )
    static let text3 = color(
        light: nsColor(0.216, 0.208, 0.184, 0.46),
        dark: nsColor(0.925, 0.905, 0.860, 0.48)
    )
    static let faint = color(
        light: nsColor(0.216, 0.208, 0.184, 0.28),
        dark: nsColor(0.925, 0.905, 0.860, 0.30)
    )
    static let border = color(
        light: nsColor(0.216, 0.208, 0.184, 0.10),
        dark: nsColor(0.925, 0.905, 0.860, 0.12)
    )
    static let strongBorder = color(
        light: nsColor(0.216, 0.208, 0.184, 0.17),
        dark: nsColor(0.925, 0.905, 0.860, 0.22)
    )
    static let windowStroke = color(
        light: nsColor(0.0, 0.0, 0.0, 0.14),
        dark: nsColor(1.0, 0.96, 0.88, 0.14)
    )
    static let panelStroke = color(
        light: nsColor(1.0, 1.0, 1.0, 0.55),
        dark: nsColor(1.0, 0.96, 0.88, 0.18)
    )
    static let inputBackground = color(
        light: nsColor(1.0, 1.0, 1.0, 0.48),
        dark: nsColor(0.190, 0.178, 0.156, 0.62)
    )
    static let accent = color(
        light: nsColor(0.137, 0.514, 0.887),
        dark: nsColor(0.355, 0.635, 0.960)
    )
    static let accentSoft = color(
        light: nsColor(0.137, 0.514, 0.887, 0.12),
        dark: nsColor(0.355, 0.635, 0.960, 0.20)
    )
    static let overdue = color(
        light: nsColor(0.72, 0.22, 0.18),
        dark: nsColor(0.980, 0.420, 0.360)
    )
    static let today = color(
        light: nsColor(0.78, 0.42, 0.12),
        dark: nsColor(0.960, 0.640, 0.300)
    )

    static let inputTextNSColor = adaptiveNSColor(
        light: nsColor(0.216, 0.208, 0.184),
        dark: nsColor(0.925, 0.905, 0.860)
    )
    static let placeholderNSColor = adaptiveNSColor(
        light: nsColor(0.216, 0.208, 0.184, 0.50),
        dark: nsColor(0.925, 0.905, 0.860, 0.42)
    )

    private static func color(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: adaptiveNSColor(light: light, dark: dark))
    }

    private static func adaptiveNSColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    private static func nsColor(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
    }
}

private let emojiPalette = [
    "🔥", "⭐", "👥", "🗑️", "💼", "🎯", "📌", "⚡",
    "✅", "🧠", "💡", "📚", "🛠️", "🌱", "☕", "🎨",
    "📝", "📅", "💬", "🚀", "🧩", "🔔", "🏷️", "🌙",
    "⏰", "📂", "🔒", "💎", "🍅", "🏃", "💤", "❓"
]

@MainActor
final class HistoryWindowController: NSWindowController {
    private let store: BoardStore
    private let themeStore: ThemePreferenceStore
    private var keyMonitor: Any?

    init(store: BoardStore, themeStore: ThemePreferenceStore) {
        self.store = store
        self.themeStore = themeStore

        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let hostingController = NSHostingController(
            rootView: HistoryOverlayView(store: store, themeStore: themeStore, onClose: {})
        )
        let window = DesktopWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "时间机器"
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.canHide = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.level = .screenSaver
        window.contentViewController = hostingController

        super.init(window: window)

        hostingController.rootView = HistoryOverlayView(store: store, themeStore: themeStore, onClose: { [weak self] in
            self?.hide()
        })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        store.ensureCurrentDaySnapshot()

        if let screenFrame = NSScreen.main?.frame {
            window?.setFrame(screenFrame, display: true)
        }

        installKeyMonitor()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(window?.contentView)
    }

    private func hide() {
        removeKeyMonitor()
        window?.orderOut(nil)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.hide()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    deinit {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }
}

private enum HistoryStyle {
    static let timeMachineRed = Color(red: 0.92, green: 0.16, blue: 0.18)
    static let timelineLine = Color.white.opacity(0.22)
    static let glassFill = Color.white.opacity(0.12)
    static let glassStroke = Color.white.opacity(0.18)
    static let depthWindowCount = 13
}

struct HistoryOverlayView: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var themeStore: ThemePreferenceStore
    let onClose: () -> Void
    @State private var selectedDateID: String
    @State private var searchQuery = ""
    @State private var highlightedTodoID: UUID?

    init(store: BoardStore, themeStore: ThemePreferenceStore, onClose: @escaping () -> Void) {
        self.store = store
        self.themeStore = themeStore
        self.onClose = onClose
        _selectedDateID = State(initialValue: store.latestSnapshotDateID ?? DateText.iso(from: Date()))
    }

    private var selectedSnapshot: DailyBoardSnapshot? {
        store.snapshot(for: selectedDateID)
    }

    private var searchResults: [HistorySearchResult] {
        HistorySearchResult.results(in: store.historySnapshots, query: searchQuery)
    }

    var body: some View {
        GeometryReader { proxy in
            let timelineWidth = min(max(proxy.size.width * 0.11, 138), 170)
            let maxPanelWidth = max(620, proxy.size.width - timelineWidth - 220)
            let panelWidth = min(max(proxy.size.width * 0.58, 720), min(1040, maxPanelWidth))
            let depthHeight = min(max(proxy.size.height * 0.24, 190), 250)
            let trimmedSearchQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchListHeight = trimmedSearchQuery.isEmpty
                ? CGFloat(0)
                : min(max(CGFloat(max(searchResults.count, 1)) * 32, 32), 154)
            let searchHeight = CGFloat(16 + 34) + (trimmedSearchQuery.isEmpty ? 0 : CGFloat(8) + searchListHeight)
            let searchGap: CGFloat = 24
            let panelHeight = min(max(proxy.size.height * 0.56, 420), max(360, proxy.size.height - depthHeight - searchHeight - searchGap - 54))
            let stackWidth = panelWidth + 84
            let stackHeight = panelHeight + depthHeight
            let searchWidth = min(max(panelWidth * 0.70, 560), panelWidth - 72)
            let panelCenterY = min(
                max(proxy.size.height * 0.50, depthHeight + panelHeight / 2 + 22),
                proxy.size.height - panelHeight / 2 - searchGap - searchHeight / 2 - 24
            )
            let stackCenterY = panelCenterY - depthHeight / 2
            let timelineCenterX = min(
                proxy.size.width - timelineWidth / 2 - 42,
                proxy.size.width / 2 + panelWidth / 2 + timelineWidth / 2 + 46
            )

            ZStack {
                HistoryBackdrop()

                ZStack(alignment: .bottom) {
                    ForEach(Array((1...HistoryStyle.depthWindowCount).reversed()), id: \.self) { depth in
                        let dateID = DateText.dateID(byAdding: -depth, to: selectedDateID)
                        let hasSnapshot = dateID.map { store.hasSnapshot(on: $0) } ?? false

                        HistoryGhostWindow(
                            depth: depth,
                            dateID: dateID,
                            hasSnapshot: hasSnapshot
                        )
                            .frame(
                                width: panelWidth - CGFloat(depth * 15),
                                height: panelHeight - CGFloat(depth * 3)
                            )
                            .offset(y: -CGFloat(depth) * 14)
                            .scaleEffect(1 - CGFloat(depth) * 0.010, anchor: .bottom)
                            .blur(radius: CGFloat(max(depth - 8, 0)) * 0.12)
                    }

                    HistorySnapshotPanel(
                        snapshot: selectedSnapshot,
                        selectedDateID: selectedDateID,
                        highlightedTodoID: highlightedTodoID
                    )
                    .frame(width: panelWidth, height: panelHeight)
                }
                .frame(width: stackWidth, height: stackHeight, alignment: .bottom)
                .position(x: proxy.size.width / 2, y: stackCenterY)

                HistoryTimelineView(
                    store: store,
                    selectedDateID: $selectedDateID
                )
                .frame(width: timelineWidth, height: panelHeight)
                .position(x: timelineCenterX, y: panelCenterY)

                HistorySearchBar(
                    query: $searchQuery,
                    results: searchResults,
                    selectedDateID: selectedDateID,
                    resultListHeight: searchListHeight
                ) { result in
                    selectSearchResult(result)
                }
                .frame(width: searchWidth, height: searchHeight, alignment: .top)
                .position(x: proxy.size.width / 2, y: panelCenterY + panelHeight / 2 + searchGap + searchHeight / 2)
                .onChange(of: searchResults) { results in
                    let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        highlightedTodoID = nil
                        return
                    }
                    guard let firstResult = results.first else { return }
                    if let selectedResult = results.first(where: { $0.dateID == selectedDateID }) {
                        highlightedTodoID = selectedResult.primaryTodoID
                    } else {
                        selectSearchResult(firstResult)
                    }
                }
                .onChange(of: selectedDateID) { dateID in
                    let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else {
                        highlightedTodoID = nil
                        return
                    }
                    highlightedTodoID = searchResults.first { $0.dateID == dateID }?.primaryTodoID
                }

                VStack {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.78))
                                .frame(width: 34, height: 34)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                        .help("关闭时间机器")
                        .accessibilityLabel("关闭时间机器")
                    }
                    .padding(.top, 28)
                    .padding(.trailing, 32)

                    Spacer()
                }
            }
        }
        .onAppear {
            store.ensureCurrentDaySnapshot()
            selectedDateID = store.latestSnapshotDateID ?? DateText.iso(from: Date())
        }
        .preferredColorScheme(themeStore.preference.colorScheme)
    }

    private func selectSearchResult(_ result: HistorySearchResult) {
        withAnimation(.easeOut(duration: 0.18)) {
            selectedDateID = result.dateID
            highlightedTodoID = result.primaryTodoID
        }
    }
}

struct HistorySearchResult: Identifiable, Equatable {
    let dateID: String
    let matchCount: Int
    let previewText: String
    let quadrantTitle: String
    let primaryTodoID: UUID

    var id: String { dateID }

    var detailText: String {
        matchCount > 1 ? "\(quadrantTitle) · \(matchCount) 项匹配" : quadrantTitle
    }

    static func results(in snapshots: [DailyBoardSnapshot], query: String) -> [HistorySearchResult] {
        let terms = query
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        guard !terms.isEmpty else { return [] }

        return snapshots
            .sorted { $0.dateID > $1.dateID }
            .compactMap { snapshot in
                result(in: snapshot, terms: terms)
            }
    }

    private static func result(in snapshot: DailyBoardSnapshot, terms: [String]) -> HistorySearchResult? {
        var matchCount = 0
        var previewText: String?
        var quadrantTitle: String?
        var primaryTodoID: UUID?

        for quadrant in snapshot.board.quadrants {
            for todo in SnapshotProjection.visibleTodos(in: quadrant, on: snapshot.dateID) where matches(todo: todo, quadrant: quadrant, terms: terms) {
                matchCount += 1
                if previewText == nil {
                    previewText = todo.text
                    quadrantTitle = quadrant.title
                    primaryTodoID = todo.id
                }
            }
        }

        guard let previewText, let quadrantTitle, let primaryTodoID, matchCount > 0 else { return nil }
        return HistorySearchResult(
            dateID: snapshot.dateID,
            matchCount: matchCount,
            previewText: previewText,
            quadrantTitle: quadrantTitle,
            primaryTodoID: primaryTodoID
        )
    }

    private static func matches(todo: Todo, quadrant: Quadrant, terms: [String]) -> Bool {
        let haystacks = [todo.text, quadrant.title, quadrant.subtitle]
        return terms.allSatisfy { term in
            haystacks.contains { text in
                text.localizedCaseInsensitiveContains(term)
            }
        }
    }
}

struct HistorySearchBar: View {
    @Binding var query: String
    let results: [HistorySearchResult]
    let selectedDateID: String
    let resultListHeight: CGFloat
    let onSelectResult: (HistorySearchResult) -> Void

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            searchField
            searchResultsContent
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.26), radius: 16, x: 0, y: 10)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.66))

            TextField("搜索任务，跳到那一天", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.8, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.90))
                .onSubmit(jumpToFirstResult)

            if !trimmedQuery.isEmpty {
                Text(String(results.count))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.70))
                    .frame(width: 28, height: 22)
                    .background(Color.white.opacity(0.10), in: Capsule())

                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color.black.opacity(0.20), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var searchResultsContent: some View {
        if !trimmedQuery.isEmpty {
            if results.isEmpty {
                Text("没有匹配的任务")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.48))
                    .frame(height: 30)
                    .padding(.horizontal, 5)
            } else {
                ScrollView(.vertical, showsIndicators: results.count > 4) {
                    LazyVStack(spacing: 5) {
                        ForEach(Array(results.prefix(10))) { result in
                            HistorySearchResultButton(
                                result: result,
                                selected: result.dateID == selectedDateID
                            ) {
                                onSelectResult(result)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(height: resultListHeight)
            }
        }
    }

    private func jumpToFirstResult() {
        guard let firstResult = results.first else { return }
        onSelectResult(firstResult)
    }
}

struct HistorySearchResultButton: View {
    let result: HistorySearchResult
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(DateText.historyTimelineLabel(result.dateID))
                    .font(.system(size: 11.8, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(selected ? 0.98 : 0.76))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: 66, alignment: .leading)
                    .layoutPriority(2)

                Text(result.previewText)
                    .font(.system(size: 11.8, weight: .medium))
                    .foregroundStyle(Color.white.opacity(selected ? 0.96 : 0.68))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(result.detailText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(selected ? 0.74 : 0.44))
                    .lineLimit(1)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? HistoryStyle.timeMachineRed.opacity(0.88) : Color.white.opacity(0.09))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.white.opacity(selected ? 0.28 : 0.12), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct HistoryBackdrop: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.028, blue: 0.030)

            LinearGradient(
                colors: [
                    Color(red: 0.31, green: 0.43, blue: 0.22).opacity(0.48),
                    Color(red: 0.16, green: 0.20, blue: 0.24).opacity(0.72),
                    Color(red: 0.18, green: 0.12, blue: 0.20).opacity(0.56),
                    Color.black.opacity(0.96)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.clear,
                    Color.black.opacity(0.48)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

struct HistoryGhostWindow: View {
    let depth: Int
    let dateID: String?
    let hasSnapshot: Bool

    private var shellOpacity: Double {
        max(0.20, 0.58 - Double(depth) * 0.024)
    }

    private var edgeOpacity: Double {
        max(0.055, 0.20 - Double(depth) * 0.008)
    }

    private var toolbarOpacity: Double {
        max(0.070, 0.30 - Double(depth) * 0.012)
    }

    private var shellGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.23, green: 0.22, blue: 0.19).opacity(shellOpacity),
                Color(red: 0.13, green: 0.125, blue: 0.11).opacity(shellOpacity + 0.06),
                Color(red: 0.08, green: 0.078, blue: 0.074).opacity(shellOpacity + 0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(shellGradient)

            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle()
                            .fill(Color.white.opacity(index == 0 ? 0.38 : 0.18))
                            .frame(width: 7, height: 7)
                    }

                    Spacer(minLength: 10)

                    if let dateID {
                        Text(DateText.historyBadgeLabel(dateID))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(hasSnapshot ? 0.46 : 0.24))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(Color.white.opacity(toolbarOpacity * 0.22))

                Rectangle()
                    .fill(Color.white.opacity(max(0.018, 0.075 - Double(depth) * 0.004)))
                    .frame(height: 1)

                HistoryGhostContentHint(depth: depth, hasSnapshot: hasSnapshot)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(edgeOpacity), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(max(0.18, 0.36 - Double(depth) * 0.010)), radius: 24, x: 0, y: 18)
    }
}

struct HistoryGhostContentHint: View {
    let depth: Int
    let hasSnapshot: Bool

    private var lineOpacity: Double {
        if hasSnapshot {
            return max(0.020, 0.090 - Double(depth) * 0.004)
        }
        return max(0.012, 0.038 - Double(depth) * 0.002)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let x = width * 0.5
            let y = height * 0.5

            ZStack(alignment: .topLeading) {
                VStack(spacing: 1) {
                    HStack(spacing: 1) {
                        ghostPane(index: 0)
                            .frame(width: x, height: y)
                        ghostPane(index: 1)
                            .frame(width: width - x - 1, height: y)
                    }

                    HStack(spacing: 1) {
                        ghostPane(index: 2)
                            .frame(width: x, height: height - y - 1)
                        ghostPane(index: 3)
                            .frame(width: width - x - 1, height: height - y - 1)
                    }
                }

                Rectangle()
                    .fill(Color.white.opacity(lineOpacity))
                    .frame(width: 1, height: height)
                    .position(x: x + 0.5, y: height / 2)

                Rectangle()
                    .fill(Color.white.opacity(lineOpacity))
                    .frame(width: width, height: 1)
                    .position(x: width / 2, y: y + 0.5)
            }
        }
    }

    private func ghostPane(index: Int) -> some View {
        let activeOpacity = max(0.010, 0.035 - Double(depth) * 0.002)
        let emptyOpacity = max(0.006, 0.016 - Double(depth) * 0.001)

        return ZStack(alignment: .topLeading) {
            Color.white.opacity(hasSnapshot ? activeOpacity : emptyOpacity)

            VStack(alignment: .leading, spacing: 5) {
                ForEach(0..<3, id: \.self) { row in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.white.opacity(hasSnapshot ? lineOpacity : lineOpacity * 0.50))
                        .frame(width: CGFloat(44 + row * 18 + index * 7), height: 3)
                }
            }
            .padding(.top, 18)
            .padding(.leading, 18)
        }
    }
}

struct HistorySnapshotPanel: View {
    let snapshot: DailyBoardSnapshot?
    let selectedDateID: String
    let highlightedTodoID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HistoryWindowControls()
                    .padding(.trailing, 4)

                BrandMark()
                    .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(DateText.historyFullTitle(selectedDateID))
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(Palette.text)

                    Text(DateText.historyStatus(for: selectedDateID))
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.text3)
                }

                Spacer()

                Text(DateText.historyBadgeLabel(selectedDateID))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(HistoryStyle.timeMachineRed)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Palette.softBackground, in: Capsule())
            }
            .padding(.horizontal, 18)
            .frame(height: 60)
            .background(.thinMaterial)
            .background(Palette.titleBarGlassTint)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Palette.border)
                    .frame(height: 1)
            }

            if let snapshot {
                HistoryMatrixView(
                    board: snapshot.board,
                    selectedDateID: selectedDateID,
                    highlightedTodoID: highlightedTodoID
                )
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(Palette.text3)
                    Text("这天没有任务记录")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.text2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.quadrantGlassTint)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(Palette.mainWindowGlassTint)
        }
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Palette.panelStroke, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.40), radius: 36, x: 0, y: 26)
    }
}

struct HistoryWindowControls: View {
    private let colors = [
        Color(red: 1.00, green: 0.36, blue: 0.31),
        Color(red: 1.00, green: 0.74, blue: 0.20),
        Color(red: 0.33, green: 0.78, blue: 0.28)
    ]

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color.opacity(0.88))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.black.opacity(0.10), lineWidth: 0.5))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct HistoryMatrixView: View {
    let board: BoardState
    let selectedDateID: String
    let highlightedTodoID: UUID?

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = max(proxy.size.height, 1)
            let x = width * 0.5
            let y = height * 0.5
            let rightWidth = max(width - x - 1, 1)
            let bottomHeight = max(height - y - 1, 1)

            ZStack(alignment: .topLeading) {
                VStack(spacing: 1) {
                    HStack(spacing: 1) {
                        HistoryQuadrantSnapshotView(
                            quadrant: quadrant(.q1),
                            selectedDateID: selectedDateID,
                            highlightedTodoID: highlightedTodoID
                        )
                            .frame(width: x, height: y)
                        HistoryQuadrantSnapshotView(
                            quadrant: quadrant(.q2),
                            selectedDateID: selectedDateID,
                            highlightedTodoID: highlightedTodoID
                        )
                            .frame(width: rightWidth, height: y)
                    }
                    HStack(spacing: 1) {
                        HistoryQuadrantSnapshotView(
                            quadrant: quadrant(.q3),
                            selectedDateID: selectedDateID,
                            highlightedTodoID: highlightedTodoID
                        )
                            .frame(width: x, height: bottomHeight)
                        HistoryQuadrantSnapshotView(
                            quadrant: quadrant(.q4),
                            selectedDateID: selectedDateID,
                            highlightedTodoID: highlightedTodoID
                        )
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
            }
        }
    }

    private func quadrant(_ id: QuadrantID) -> Quadrant {
        board.quadrants.first { $0.id == id } ?? .default(id)
    }
}

struct HistoryQuadrantSnapshotView: View {
    let quadrant: Quadrant
    let selectedDateID: String
    let highlightedTodoID: UUID?

    private var projectedTodos: [Todo] {
        SnapshotProjection.visibleTodos(in: quadrant, on: selectedDateID)
    }

    private var activeTodos: [Todo] {
        projectedTodos.filter { !$0.done }
    }

    private var completedOnSelectedDate: [Todo] {
        projectedTodos
            .filter(\.done)
            .sorted { lhs, rhs in
                let lhsDate = lhs.completedAt ?? .distantPast
                let rhsDate = rhs.completedAt ?? .distantPast
                if lhsDate != rhsDate {
                    return lhsDate > rhsDate
                }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    private var visibleTodos: [Todo] {
        activeTodos + completedOnSelectedDate
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(quadrant.emoji)
                    .font(.system(size: 18))
                    .frame(width: 26, height: 26)

                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(quadrant.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text("· \(quadrant.subtitle)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.text3)
                }

                Spacer(minLength: 8)

                Text("\(activeTodos.count)")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.text3)
                    .frame(minWidth: 18)
            }
            .padding(.top, 18)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(visibleTodos) { todo in
                            HistoryTodoRow(
                                todo: todo,
                                isHighlighted: todo.id == highlightedTodoID
                            )
                            .id(todo.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .onChange(of: highlightedTodoID) { todoID in
                    scrollToHighlightedTodo(todoID, with: scrollProxy)
                }
                .onAppear {
                    scrollToHighlightedTodo(highlightedTodoID, with: scrollProxy)
                }
            }
        }
        .background(Palette.quadrantGlassTint)
    }

    private func scrollToHighlightedTodo(_ todoID: UUID?, with scrollProxy: ScrollViewProxy) {
        guard let todoID, visibleTodos.contains(where: { $0.id == todoID }) else { return }
        withAnimation(.easeOut(duration: 0.20)) {
            scrollProxy.scrollTo(todoID, anchor: .center)
        }
    }
}

struct HistoryTodoRow: View {
    let todo: Todo
    let isHighlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(todo.done ? Palette.accent : Palette.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(todo.done ? Palette.accent : Palette.strongBorder, lineWidth: 1.4)
                    )

                if todo.done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
            .frame(width: 15, height: 15)
            .padding(.top, 2)

            Text(todo.text)
                .font(.system(size: 13.2))
                .foregroundStyle(isHighlighted ? Palette.text : (todo.done ? Palette.faint : Palette.text))
                .strikethrough(todo.done, color: Palette.faint)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(isHighlighted ? Palette.accent.opacity(0.90) : Color.clear, lineWidth: 1.2)
        )
        .shadow(color: isHighlighted ? Palette.accent.opacity(0.20) : .clear, radius: 7, x: 0, y: 0)
    }

    private var rowBackground: Color {
        if isHighlighted {
            return Palette.accent.opacity(0.26)
        }
        return todo.done ? Color.clear : Palette.hoverBackground.opacity(0.35)
    }
}

struct HistoryTimelineView: View {
    @ObservedObject var store: BoardStore
    @Binding var selectedDateID: String

    private var timelineDateIDs: [String] {
        (-4...4).compactMap { DateText.dateID(byAdding: $0, to: selectedDateID) }
    }

    private var canGoPrevious: Bool {
        guard let earliest = store.earliestSnapshotDateID else { return false }
        return selectedDateID > earliest
    }

    private var canGoNext: Bool {
        selectedDateID < DateText.iso(from: Date())
    }

    var body: some View {
        VStack(spacing: 12) {
            Button {
                moveSelection(by: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(canGoPrevious ? Color.white.opacity(0.92) : Color.white.opacity(0.28))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(canGoPrevious ? 0.18 : 0.08), lineWidth: 1))
            .disabled(!canGoPrevious)
            .help("前一天")

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(HistoryStyle.timelineLine)
                    .frame(width: 2)
                    .padding(.leading, 18)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(timelineDateIDs, id: \.self) { dateID in
                        TimelineDateButton(
                            dateID: dateID,
                            selected: dateID == selectedDateID,
                            hasSnapshot: store.hasSnapshot(on: dateID),
                            enabled: isSelectable(dateID)
                        ) {
                            selectedDateID = dateID
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .padding(.vertical, 2)

            Button {
                moveSelection(by: 1)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(canGoNext ? Color.white.opacity(0.92) : Color.white.opacity(0.28))
                    .frame(width: 32, height: 32)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(canGoNext ? 0.18 : 0.08), lineWidth: 1))
            .disabled(!canGoNext)
            .help("后一天")
        }
        .padding(.vertical, 6)
    }

    private func moveSelection(by days: Int) {
        guard let nextDateID = DateText.dateID(byAdding: days, to: selectedDateID) else { return }
        guard isSelectable(nextDateID) else {
            return
        }
        selectedDateID = nextDateID
    }

    private func isSelectable(_ dateID: String) -> Bool {
        if let earliest = store.earliestSnapshotDateID, dateID < earliest {
            return false
        }
        if dateID > DateText.iso(from: Date()) {
            return false
        }
        return true
    }
}

struct TimelineDateButton: View {
    let dateID: String
    let selected: Bool
    let hasSnapshot: Bool
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(selected ? HistoryStyle.timeMachineRed : Color.white.opacity(enabled ? (hasSnapshot ? 0.46 : 0.20) : 0.10))
                        .frame(width: selected ? 14 : 8, height: selected ? 14 : 8)
                    Circle()
                        .stroke(selected ? HistoryStyle.timeMachineRed.opacity(0.28) : Color.clear, lineWidth: 8)
                        .frame(width: 14, height: 14)
                }
                .frame(width: 38, height: 28)

                VStack(alignment: .leading, spacing: 0) {
                    Text(DateText.historyTimelineLabel(dateID))
                        .font(.system(size: selected ? 13.2 : 12.0, weight: selected ? .semibold : .medium))
                        .foregroundStyle(Color.white.opacity(enabled ? (selected ? 0.98 : 0.66) : 0.30))
                        .lineLimit(1)
                }
                .padding(.horizontal, selected ? 9 : 0)
                .padding(.vertical, selected ? 7 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? HistoryStyle.timeMachineRed.opacity(0.88) : Color.clear)
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct ContentView: View {
    @ObservedObject var store: BoardStore
    @ObservedObject var themeStore: ThemePreferenceStore
    let openHistory: () -> Void
    let prepareForInterfaceInteraction: () -> Void
    let returnToDesktopLayer: () -> Void
    @State private var now = Date()
    @AppStorage("quadrantDesktop.windowOpacity") private var windowOpacity = 1.0

    var body: some View {
        VStack(spacing: 0) {
            TitleBarView(
                now: now,
                windowOpacity: $windowOpacity,
                openHistory: openHistory,
                prepareForInterfaceInteraction: prepareForInterfaceInteraction,
                returnToDesktopLayer: returnToDesktopLayer
            )
            MatrixView(store: store)
        }
        .frame(minWidth: 680, minHeight: 440)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Palette.mainWindowGlassTint)
        }
        .background(WindowOpacityBinder(opacity: windowOpacity).frame(width: 0, height: 0))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Palette.windowStroke, lineWidth: 0.8)
        )
        .preferredColorScheme(themeStore.preference.colorScheme)
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { date in
            now = date
            store.ensureCurrentDaySnapshot(at: date)
        }
        .onAppear {
            store.ensureCurrentDaySnapshot()
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
    let onMouseDown: () -> Void

    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ nsView: DragView, context: Context) {
        nsView.onMouseDown = onMouseDown
    }

    final class DragView: NSView {
        var onMouseDown: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            onMouseDown?()
            window?.makeKey()
        }

        override func mouseDragged(with event: NSEvent) {
            onMouseDown?()
            window?.performDrag(with: event)
        }
    }
}

struct TitleBarView: View {
    let now: Date
    @Binding var windowOpacity: Double
    let openHistory: () -> Void
    let prepareForInterfaceInteraction: () -> Void
    let returnToDesktopLayer: () -> Void

    var body: some View {
        ZStack {
            WindowDragArea(onMouseDown: prepareForInterfaceInteraction)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(spacing: 14) {
                Button(action: returnToDesktopLayer) {
                    BrandMark()
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 18)
                .help("回到桌面底部")
                .accessibilityLabel("回到桌面底部")

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

                Button(action: openHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Palette.text2)
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background(.thinMaterial, in: Circle())
                .background(Palette.controlGlassTint, in: Circle())
                .overlay(Circle().stroke(Palette.panelStroke, lineWidth: 0.7))
                .help("查看时间机器")
                .accessibilityLabel("查看时间机器")
            }
            .padding(.trailing, 16)
        }
        .frame(height: 44)
        .background {
            Rectangle()
                .fill(.thinMaterial)
            Rectangle()
                .fill(Palette.titleBarGlassTint)
        }
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
        .background(.thinMaterial, in: Capsule())
        .background(Palette.controlGlassTint, in: Capsule())
        .overlay(Capsule().stroke(Palette.panelStroke, lineWidth: 0.7))
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
            let xRange = MatrixLayoutLimits.splitRange(
                totalLength: width,
                minimumLength: MatrixLayoutLimits.minQuadrantWidth
            )
            let yRange = MatrixLayoutLimits.splitRange(
                totalLength: height,
                minimumLength: MatrixLayoutLimits.minQuadrantHeight
            )
            let splitX = MatrixLayoutLimits.clamp(store.board.splitX, to: xRange)
            let splitY = MatrixLayoutLimits.clamp(store.board.splitY, to: yRange)
            let x = width * splitX
            let y = height * splitY
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
                                    y: Double(value.location.y / height),
                                    xRange: xRange,
                                    yRange: yRange
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
        .background {
            Rectangle()
                .fill(.thinMaterial)
            Rectangle()
                .fill(Palette.quadrantGlassTint)
            if isDropTargeted {
                Rectangle()
                    .fill(Palette.accentSoft)
            }
        }
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
                        .lineLimit(1)
                        .layoutPriority(2)

                    Text("· \(quadrant.subtitle)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.text3)
                        .lineLimit(1)
                        .layoutPriority(1)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.90)
            .layoutPriority(1)

            Spacer(minLength: 8)

            Button(action: beginAdding) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Palette.text3)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                Circle()
                    .fill(Palette.softBackground.opacity(0.72))
            )
            .help("新增任务")
            .accessibilityLabel("新增任务")
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
        if let activeAddQuadrant = store.activeAddQuadrant {
            NSApp.keyWindow?.makeFirstResponder(NSApp.keyWindow?.contentView)

            if activeAddQuadrant == id {
                DispatchQueue.main.async {
                    store.finishActiveAdd()
                }
            } else {
                DispatchQueue.main.async {
                    store.finishActiveAdd()
                    store.activateAdd(to: id)
                    addFocusSerial += 1
                }
            }
            return
        }

        guard store.beginAddFromBlankTap(to: id) else { return }
        addFocusSerial += 1
    }

    private func beginAdding() {
        if store.activeAddQuadrant == id {
            addFocusSerial += 1
            return
        }

        if store.activeAddQuadrant != nil {
            NSApp.keyWindow?.makeFirstResponder(NSApp.keyWindow?.contentView)
            DispatchQueue.main.async {
                store.finishActiveAdd()
                store.activateAdd(to: id)
                addFocusSerial += 1
            }
            return
        }

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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .background(Palette.inputBackground, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Palette.accent.opacity(0.22), lineWidth: 1)
        )
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
        textField.textColor = Palette.inputTextNSColor
        textField.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: Palette.placeholderNSColor,
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
                .foregroundColor: Palette.placeholderNSColor,
                .font: NSFont.systemFont(ofSize: 13.5)
            ]
        )
        nsView.textColor = Palette.inputTextNSColor

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
            if let textField = notification.object as? NSTextField,
               let editor = textField.currentEditor() as? NSTextView {
                editor.insertionPointColor = NSColor.systemBlue
                editor.textColor = Palette.inputTextNSColor
            }
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

            todoTitle(todo)
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

    @ViewBuilder
    private func todoTitle(_ todo: Todo) -> some View {
        if todo.done {
            Text(todo.text)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.faint)
                .strikethrough(true, color: Palette.faint)
                .lineLimit(1)
                .frame(height: 22)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            TextField("", text: Binding(
                get: { store.todo(todoID)?.text ?? "" },
                set: { store.updateTodo(todoID, text: $0) }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .foregroundStyle(Palette.text)
            .frame(height: 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onSubmit {
                onReturn()
            }
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

    static func historyFullTitle(_ dateID: String) -> String {
        guard let date = date(from: dateID) else { return dateID }
        let components = Calendar.current.dateComponents([.year, .month, .day, .weekday], from: date)
        let week = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        let weekday = components.weekday.flatMap { week[safe: $0 - 1] } ?? ""
        return "\(components.year ?? 2000)年\(components.month ?? 1)月\(components.day ?? 1)日 · \(weekday)"
    }

    static func historyTimelineLabel(_ dateID: String) -> String {
        guard let date = date(from: dateID) else { return dateID }
        let today = Calendar.current.startOfDay(for: Date())
        let day = Calendar.current.startOfDay(for: date)
        let diff = Calendar.current.dateComponents([.day], from: today, to: day).day ?? 0

        if diff == 0 { return "今天" }
        if diff == -1 { return "昨天" }
        if diff == 1 { return "明天" }

        let components = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 1)月\(components.day ?? 1)日"
    }

    static func historyBadgeLabel(_ dateID: String) -> String {
        guard let date = date(from: dateID) else { return dateID }
        let components = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(components.month ?? 1)月\(components.day ?? 1)日"
    }

    static func historyStatus(for dateID: String) -> String {
        if dateID == iso(from: Date()) {
            return "今日进行中"
        }
        return "24:00 状态"
    }

    static func dateID(byAdding days: Int, to dateID: String) -> String? {
        guard
            let date = date(from: dateID),
            let adjusted = Calendar.current.date(byAdding: .day, value: days, to: date)
        else {
            return nil
        }

        return iso(from: adjusted)
    }

    static func endOfDay(for dateID: String) -> Date? {
        guard let day = date(from: dateID) else { return nil }
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: day)
    }

    static func isDate(_ date: Date, sameDayAs dateID: String) -> Bool {
        guard let targetDate = self.date(from: dateID) else { return false }
        return Calendar.current.isDate(date, inSameDayAs: targetDate)
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
