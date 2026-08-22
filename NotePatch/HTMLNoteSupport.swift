import SwiftUI
import WebKit

@MainActor
final class NoteWebViewRuntime {
    static let shared = NoteWebViewRuntime()

    private var didSchedulePrewarm = false
    private var prewarmWebView: WKWebView?

    private init() {}

    func configuration(allowsContentJavaScript: Bool) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = allowsContentJavaScript
        return configuration
    }

    func prewarmAfterInterfaceSettles() async {
        guard !didSchedulePrewarm else { return }
        didSchedulePrewarm = true
        do {
            try await Task.sleep(nanoseconds: 450_000_000)
        } catch {
            didSchedulePrewarm = false
            return
        }
        guard !Task.isCancelled else {
            didSchedulePrewarm = false
            return
        }

        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1, height: 1),
            configuration: configuration(allowsContentJavaScript: false)
        )
        prewarmWebView = webView
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)

        try? await Task.sleep(nanoseconds: 1_500_000_000)
        if prewarmWebView === webView {
            prewarmWebView = nil
        }
    }
}

enum HTMLNoteCommand: Equatable {
    case undo
    case redo
    case bold
    case italic
    case heading2
    case unorderedList
    case orderedList
    case fontSize(Int)

    var javascriptArguments: (command: String, value: String?) {
        switch self {
        case .undo: return ("undo", nil)
        case .redo: return ("redo", nil)
        case .bold: return ("bold", nil)
        case .italic: return ("italic", nil)
        case .heading2: return ("formatBlock", "h2")
        case .unorderedList: return ("insertUnorderedList", nil)
        case .orderedList: return ("insertOrderedList", nil)
        case let .fontSize(size): return ("fontSizePx", String(HTMLNoteFontSize.normalized(size)))
        }
    }
}

enum HTMLNoteFontSize {
    static let presets = [12, 14, 17, 20, 24, 28, 32, 40]
    static let defaultSize = 17

    static func normalized(_ size: Int) -> Int {
        presets.min(by: { abs($0 - size) < abs($1 - size) }) ?? defaultSize
    }

    static func smaller(than size: Int) -> Int? {
        let current = normalized(size)
        return presets.last(where: { $0 < current })
    }

    static func larger(than size: Int) -> Int? {
        let current = normalized(size)
        return presets.first(where: { $0 > current })
    }
}

enum HTMLNoteSecurity {
    nonisolated static let contentSecurityPolicy = "default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src 'none'; media-src 'none'; frame-src 'none'; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; script-src 'none'"

    nonisolated static func readerDocument(bodyHTML: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
          <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
          <style>
            :root { color-scheme: light dark; }
            html, body { margin: 0; padding: 0; background: transparent; }
            body { padding: 20px; color: -apple-system-label; font: -apple-system-body; line-height: 1.58; overflow-wrap: anywhere; }
            h1, h2, h3, h4 { line-height: 1.25; margin: 1.2em 0 .55em; }
            h1:first-child, h2:first-child, h3:first-child { margin-top: 0; }
            img, video { max-width: 100%; height: auto; }
            pre, code { white-space: pre-wrap; overflow-wrap: anywhere; font-family: ui-monospace, Menlo, monospace; }
            pre { padding: 12px; border-radius: 8px; background: rgba(127,127,127,.12); }
            blockquote { margin-left: 0; padding-left: 14px; border-left: 3px solid #0a9bf5; color: -apple-system-secondary-label; }
            table { width: 100%; border-collapse: collapse; }
            th, td { padding: 7px; border: 1px solid rgba(127,127,127,.35); text-align: left; }
            a { color: #0a84ff; }
            .np-font-size-12 { font-size: 12px; }
            .np-font-size-14 { font-size: 14px; }
            .np-font-size-17 { font-size: 17px; }
            .np-font-size-20 { font-size: 20px; }
            .np-font-size-24 { font-size: 24px; }
            .np-font-size-28 { font-size: 28px; }
            .np-font-size-32 { font-size: 32px; }
            .np-font-size-40 { font-size: 40px; }
          </style>
        </head>
        <body>\(bodyHTML)</body>
        </html>
        """
    }

    nonisolated static func editorDocument() -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
          <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
          <style>
            :root { color-scheme: light dark; }
            html, body { min-height: 100%; margin: 0; background: transparent; }
            body { box-sizing: border-box; padding: 14px; color: -apple-system-label; font: -apple-system-body; line-height: 1.55; overflow-wrap: anywhere; }
            body:focus { outline: none; }
            h1, h2, h3, h4 { line-height: 1.25; }
            img { max-width: 100%; height: auto; }
            pre, code { white-space: pre-wrap; overflow-wrap: anywhere; font-family: ui-monospace, Menlo, monospace; }
            blockquote { margin-left: 0; padding-left: 12px; border-left: 3px solid #0a9bf5; }
            font[face="notepatch-size-12"] { font-family: inherit; font-size: 12px; }
            font[face="notepatch-size-14"] { font-family: inherit; font-size: 14px; }
            font[face="notepatch-size-17"] { font-family: inherit; font-size: 17px; }
            font[face="notepatch-size-20"] { font-family: inherit; font-size: 20px; }
            font[face="notepatch-size-24"] { font-family: inherit; font-size: 24px; }
            font[face="notepatch-size-28"] { font-family: inherit; font-size: 28px; }
            font[face="notepatch-size-32"] { font-family: inherit; font-size: 32px; }
            font[face="notepatch-size-40"] { font-family: inherit; font-size: 40px; }
            .np-font-size-12 { font-size: 12px; }
            .np-font-size-14 { font-size: 14px; }
            .np-font-size-17 { font-size: 17px; }
            .np-font-size-20 { font-size: 20px; }
            .np-font-size-24 { font-size: 24px; }
            .np-font-size-28 { font-size: 28px; }
            .np-font-size-32 { font-size: 32px; }
            .np-font-size-40 { font-size: 40px; }
          </style>
        </head>
        <body contenteditable="true" spellcheck="true"></body>
        </html>
        """
    }

    nonisolated static func hasVisibleContent(_ html: String) -> Bool {
        var value = html
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "&#160;", with: " ", options: .caseInsensitive)
            .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
        value = value.replacingOccurrences(of: "\u{200B}", with: "")
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated static let editorUserScript = #"""
    (() => {
      const allowedFontSizes = [12, 14, 17, 20, 24, 28, 32, 40];
      const fontSizeMarkerPrefix = 'notepatch-size-';
      const blockedTags = new Set(['SCRIPT','IFRAME','OBJECT','EMBED','LINK','META','BASE','FORM','INPUT','BUTTON','TEXTAREA','SELECT','OPTION','STYLE','SVG','MATH']);
      let savedRange = null;
      let formatTimer = null;

      function normalizedFontSize(value) {
        const parsed = Number.parseFloat(value);
        if (!Number.isFinite(parsed)) return 17;
        return allowedFontSizes.reduce((best, candidate) =>
          Math.abs(candidate - parsed) < Math.abs(best - parsed) ? candidate : best, 17);
      }

      function isRangeInsideEditor(range) {
        const node = range && range.commonAncestorContainer;
        return !!node && (node === document.body || document.body.contains(node));
      }

      function captureSelection() {
        const selection = window.getSelection();
        if (!selection || selection.rangeCount === 0) return false;
        const range = selection.getRangeAt(0);
        if (!isRangeInsideEditor(range)) return false;
        savedRange = range.cloneRange();
        return true;
      }

      function restoreSelection() {
        if (!savedRange || !isRangeInsideEditor(savedRange)) return false;
        document.body.focus({preventScroll: true});
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(savedRange);
        return true;
      }

      function selectionStartElement() {
        const range = savedRange || (() => {
          const selection = window.getSelection();
          return selection && selection.rangeCount ? selection.getRangeAt(0) : null;
        })();
        if (!range || !isRangeInsideEditor(range)) return document.body;
        const node = range.startContainer;
        return node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement || document.body;
      }

      function currentFontSize() {
        const element = selectionStartElement();
        const marker = element.closest && element.closest('font[face^="' + fontSizeMarkerPrefix + '"]');
        if (marker) {
          return normalizedFontSize(marker.getAttribute('face').slice(fontSizeMarkerPrefix.length));
        }
        const sizedElement = element.closest && element.closest('[class*="np-font-size-"]');
        if (sizedElement) {
          const sizeClass = Array.from(sizedElement.classList).find(value => value.startsWith('np-font-size-'));
          if (sizeClass) return normalizedFontSize(sizeClass.slice('np-font-size-'.length));
        }
        return normalizedFontSize(window.getComputedStyle(element).fontSize);
      }

      function publishFormat() {
        clearTimeout(formatTimer);
        formatTimer = setTimeout(() => {
          window.webkit.messageHandlers.noteFormatChanged.postMessage({fontSize: currentFontSize()});
        }, 30);
      }

      function normalizeFontSizeMarkers(root) {
        const markers = Array.from(root.querySelectorAll('font[face^="' + fontSizeMarkerPrefix + '"]'));
        for (const marker of markers) {
          const size = normalizedFontSize(marker.getAttribute('face').slice(fontSizeMarkerPrefix.length));
          const span = document.createElement('span');
          span.className = 'np-font-size-' + size;
          while (marker.firstChild) span.appendChild(marker.firstChild);
          marker.replaceWith(span);
        }

        for (const element of Array.from(root.querySelectorAll('[style]'))) {
          const inlineSize = element.style && element.style.fontSize;
          const match = inlineSize && inlineSize.match(/^([0-9]+(?:\.[0-9]+)?)px$/i);
          if (!match) continue;
          const size = normalizedFontSize(match[1]);
          for (const className of Array.from(element.classList)) {
            if (className.startsWith('np-font-size-')) element.classList.remove(className);
          }
          element.classList.add('np-font-size-' + size);
          element.style.removeProperty('font-size');
          if (!element.getAttribute('style').trim()) element.removeAttribute('style');
        }
      }

      function normalizeSemanticFormatting(root) {
        const replacements = [['b', 'strong'], ['i', 'em']];
        for (const [sourceTag, targetTag] of replacements) {
          for (const element of Array.from(root.querySelectorAll(sourceTag))) {
            const replacement = document.createElement(targetTag);
            for (const attribute of Array.from(element.attributes)) {
              replacement.setAttribute(attribute.name, attribute.value);
            }
            while (element.firstChild) replacement.appendChild(element.firstChild);
            element.replaceWith(replacement);
          }
        }
      }

      function safeURL(value, isImage) {
        const candidate = (value || '').trim();
        if (!candidate) return '';
        if (isImage) return /^data:image\/(png|jpeg|jpg|gif|webp);/i.test(candidate) ? candidate : '';
        return /^(https?:|mailto:|#)/i.test(candidate) ? candidate : '';
      }
      function sanitize(html) {
        const template = document.createElement('template');
        template.innerHTML = html || '';
        normalizeFontSizeMarkers(template.content);
        normalizeSemanticFormatting(template.content);
        const elements = Array.from(template.content.querySelectorAll('*'));
        for (const element of elements) {
          if (blockedTags.has(element.tagName)) {
            element.remove();
            continue;
          }
          for (const attribute of Array.from(element.attributes)) {
            const name = attribute.name.toLowerCase();
            const value = attribute.value;
            if (name.startsWith('on') || ['srcdoc','action','formaction'].includes(name)) {
              element.removeAttribute(attribute.name);
            } else if (name === 'src') {
              const safe = safeURL(value, element.tagName === 'IMG');
              safe ? element.setAttribute('src', safe) : element.removeAttribute('src');
            } else if (name === 'href') {
              const safe = safeURL(value, false);
              safe ? element.setAttribute('href', safe) : element.removeAttribute('href');
            } else if (name === 'style' && /(url\s*\(|expression\s*\(|@import)/i.test(value)) {
              element.removeAttribute('style');
            }
          }
        }
        return template.innerHTML;
      }
      let timer = null;
      function publish() {
        clearTimeout(timer);
        timer = setTimeout(() => {
          const html = sanitize(document.body.innerHTML);
          window.webkit.messageHandlers.noteHTMLChanged.postMessage(html);
        }, 120);
      }
      document.addEventListener('input', publish);
      document.addEventListener('selectionchange', () => {
        if (captureSelection()) publishFormat();
      });
      document.addEventListener('paste', () => setTimeout(() => {
        document.body.innerHTML = sanitize(document.body.innerHTML);
        captureSelection();
        publishFormat();
        publish();
      }, 0));
      window.__notePatchEditor = {
        setHTML: html => {
          document.body.innerHTML = sanitize(html);
          savedRange = null;
          publishFormat();
        },
        getHTML: () => sanitize(document.body.innerHTML),
        command: (command, value) => {
          restoreSelection() || document.body.focus({preventScroll: true});
          if (command === 'fontSizePx') {
            const size = normalizedFontSize(value);
            document.execCommand('styleWithCSS', false, false);
            document.execCommand('fontName', false, fontSizeMarkerPrefix + size);
          } else {
            document.execCommand(command, false, value || null);
          }
          captureSelection();
          publishFormat();
          publish();
        }
      };
    })();
    """#
}

struct SafeHTMLNoteView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = NoteWebViewRuntime.shared.configuration(allowsContentJavaScript: false)
        LatexMathSupport.install(into: configuration)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(HTMLNoteSecurity.readerDocument(bodyHTML: html), baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(LatexMathSupport.renderCommand)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url
            let isInternalLoad = url == nil || url?.scheme == "about"
            decisionHandler(isInternalLoad ? .allow : .cancel)
        }
    }
}

struct SafeRenderedHTMLNoteView: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let url: URL
    let onAuthorizationExpired: () -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAuthorizationExpired: onAuthorizationExpired, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = NoteWebViewRuntime.shared.configuration(allowsContentJavaScript: false)
        LatexMathSupport.install(into: configuration)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        context.coordinator.onAuthorizationExpired = onAuthorizationExpired
        context.coordinator.onFailure = onFailure
        guard context.coordinator.loadedURL != url else { return }
        context.coordinator.loadedURL = url
        context.coordinator.hasReportedFailure = false
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loadedURL: URL?
        var onAuthorizationExpired: () -> Void
        var onFailure: (String) -> Void
        var hasReportedFailure = false

        init(onAuthorizationExpired: @escaping () -> Void, onFailure: @escaping (String) -> Void) {
            self.onAuthorizationExpired = onAuthorizationExpired
            self.onFailure = onFailure
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard navigationAction.targetFrame?.isMainFrame != false else {
                decisionHandler(.cancel)
                return
            }
            let requestURL = navigationAction.request.url
            let isInitialRequest = requestURL == loadedURL && navigationAction.navigationType == .other
            decisionHandler(isInitialRequest ? .allow : .cancel)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            guard navigationResponse.isForMainFrame,
                  let response = navigationResponse.response as? HTTPURLResponse else {
                decisionHandler(.allow)
                return
            }
            if response.statusCode == 401 || response.statusCode == 403 {
                decisionHandler(.cancel)
                reportAuthorizationExpired()
            } else if !(200...299).contains(response.statusCode) {
                decisionHandler(.cancel)
                reportFailure(localizedFormat("note.reader.http_error", String(response.statusCode)))
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(LatexMathSupport.renderCommand)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            reportFailure(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            reportFailure(error.localizedDescription)
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            nil
        }

        private func reportAuthorizationExpired() {
            guard !hasReportedFailure else { return }
            hasReportedFailure = true
            DispatchQueue.main.async { [onAuthorizationExpired] in onAuthorizationExpired() }
        }

        private func reportFailure(_ message: String) {
            guard !hasReportedFailure else { return }
            hasReportedFailure = true
            DispatchQueue.main.async { [onFailure] in onFailure(message) }
        }
    }
}

struct RichHTMLNoteEditor: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var html: String
    @Binding var selectedFontSize: Int
    let command: HTMLNoteCommand?
    let commandToken: Int
    let snapshotRequestToken: Int
    let onSnapshot: (String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(html: $html, selectedFontSize: $selectedFontSize, snapshotCallback: onSnapshot)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = NoteWebViewRuntime.shared.configuration(allowsContentJavaScript: true)
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: HTMLNoteSecurity.editorUserScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(context.coordinator, name: "noteHTMLChanged")
        configuration.userContentController.add(context.coordinator, name: "noteFormatChanged")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.loadHTMLString(HTMLNoteSecurity.editorDocument(), baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        context.coordinator.binding = $html
        context.coordinator.selectedFontSizeBinding = $selectedFontSize
        context.coordinator.snapshotCallback = onSnapshot
        if context.coordinator.isReady,
           context.coordinator.lastHTML != html {
            context.coordinator.setHTML(html)
        } else {
            context.coordinator.pendingHTML = html
        }

        if commandToken != context.coordinator.lastCommandToken, let command {
            context.coordinator.lastCommandToken = commandToken
            let arguments = command.javascriptArguments
            let commandJSON = Self.javascriptString(arguments.command)
            let valueJSON = arguments.value.map(Self.javascriptString) ?? "null"
            webView.evaluateJavaScript("window.__notePatchEditor && window.__notePatchEditor.command(\(commandJSON), \(valueJSON));")
        }

        if snapshotRequestToken != context.coordinator.lastSnapshotRequestToken {
            context.coordinator.lastSnapshotRequestToken = snapshotRequestToken
            context.coordinator.captureSnapshot(requestToken: snapshotRequestToken)
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "noteHTMLChanged")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "noteFormatChanged")
        webView.navigationDelegate = nil
    }

    nonisolated private static func javascriptString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(encoded.dropFirst().dropLast())
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var binding: Binding<String>
        var selectedFontSizeBinding: Binding<Int>
        weak var webView: WKWebView?
        var pendingHTML: String
        var lastHTML: String
        var lastCommandToken = -1
        var lastSnapshotRequestToken = 0
        var snapshotCallback: (String?) -> Void
        var isReady = false

        init(
            html: Binding<String>,
            selectedFontSize: Binding<Int>,
            snapshotCallback: @escaping (String?) -> Void
        ) {
            binding = html
            selectedFontSizeBinding = selectedFontSize
            pendingHTML = html.wrappedValue
            lastHTML = html.wrappedValue
            self.snapshotCallback = snapshotCallback
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isReady = true
            setHTML(pendingHTML)
        }

        func setHTML(_ html: String) {
            guard let webView else { return }
            lastHTML = html
            pendingHTML = html
            let encoded = RichHTMLNoteEditor.javascriptString(html)
            webView.evaluateJavaScript("window.__notePatchEditor && window.__notePatchEditor.setHTML(\(encoded));")
        }

        func captureSnapshot(requestToken: Int) {
            guard isReady, let webView else {
                snapshotCallback(nil)
                return
            }
            webView.evaluateJavaScript("window.__notePatchEditor && window.__notePatchEditor.getHTML();") { [weak self] value, error in
                guard let self, self.lastSnapshotRequestToken == requestToken else { return }
                guard error == nil, let html = value as? String else {
                    self.snapshotCallback(nil)
                    return
                }
                self.lastHTML = html
                if self.binding.wrappedValue != html {
                    self.binding.wrappedValue = html
                }
                self.snapshotCallback(html)
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "noteHTMLChanged", let html = message.body as? String {
                lastHTML = html
                if binding.wrappedValue != html {
                    binding.wrappedValue = html
                }
            } else if message.name == "noteFormatChanged",
                      let state = message.body as? [String: Any],
                      let rawSize = state["fontSize"] as? NSNumber {
                let size = HTMLNoteFontSize.normalized(rawSize.intValue)
                if selectedFontSizeBinding.wrappedValue != size {
                    selectedFontSizeBinding.wrappedValue = size
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            let url = navigationAction.request.url
            let isInternalLoad = url == nil || url?.scheme == "about"
            decisionHandler(isInternalLoad ? .allow : .cancel)
        }
    }
}
