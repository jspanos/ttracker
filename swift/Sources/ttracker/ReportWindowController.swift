import AppKit
import WebKit

final class ReportWindowController: NSWindowController, WKNavigationDelegate {

    private var webView: WKWebView!
    private var db: Database?

    static var shared: ReportWindowController?

    static func show(db: Database) {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            existing.refresh(db: db)
            return
        }
        let wc = ReportWindowController()
        // Show window immediately — generation happens on a background thread.
        wc.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        shared = wc
        wc.loadReport(db: db)
    }

    override init(window: NSWindow?) {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "ttracker Report"
        win.minSize = NSSize(width: 800, height: 550)
        win.isReleasedWhenClosed = false
        win.center()

        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: win.contentView!.bounds, configuration: config)
        wv.autoresizingMask = [.width, .height]
        win.contentView?.addSubview(wv)

        super.init(window: win)
        self.webView = wv
        wv.navigationDelegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    private func loadReport(db: Database) {
        self.db = db
        refresh(db: db)
    }

    func refresh(db: Database) {
        self.db = db
        webView.loadHTMLString(loadingHTML, baseURL: nil)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let html = ReportGenerator(db: db).generate()
            let url  = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent(".ttracker/report.html")
            try? html.write(to: url, atomically: true, encoding: .utf8)
            DispatchQueue.main.async { [weak self] in
                self?.webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            }
        }
    }

    private var loadingHTML: String {
        "<html><body style='background:#0f1117;color:#8892a4;font-family:-apple-system;padding:48px;font-size:15px;'>Generating report…</body></html>"
    }

    override func windowDidLoad() {
        super.windowDidLoad()
    }
}
