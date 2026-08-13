import SwiftUI
import WebKit

enum HTMLNoteCommand: Equatable {
    case undo
    case redo
    case bold
    case italic
    case heading2
    case unorderedList
    case orderedList

    var javascriptArguments: (command: String, value: String?) {
        switch self {
        case .undo: return ("undo", nil)
        case .redo: return ("redo", nil)
        case .bold: return ("bold", nil)
        case .italic: return ("italic", nil)
        case .heading2: return ("formatBlock", "h2")
        case .unorderedList: return ("insertUnorderedList", nil)
        case .orderedList: return ("insertOrderedList", nil)
        }
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
      const blockedTags = new Set(['SCRIPT','IFRAME','OBJECT','EMBED','LINK','META','BASE','FORM','INPUT','BUTTON','TEXTAREA','SELECT','OPTION','STYLE','SVG','MATH']);
      function safeURL(value, isImage) {
        const candidate = (value || '').trim();
        if (!candidate) return '';
        if (isImage) return /^data:image\/(png|jpeg|jpg|gif|webp);/i.test(candidate) ? candidate : '';
        return /^(https?:|mailto:|#)/i.test(candidate) ? candidate : '';
      }
      function sanitize(html) {
        const template = document.createElement('template');
        template.innerHTML = html || '';
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
      document.addEventListener('paste', () => setTimeout(() => {
        document.body.innerHTML = sanitize(document.body.innerHTML);
        publish();
      }, 0));
      window.__notePatchEditor = {
        setHTML: html => { document.body.innerHTML = sanitize(html); },
        getHTML: () => sanitize(document.body.innerHTML),
        command: (command, value) => {
          document.body.focus();
          document.execCommand(command, false, value || null);
          publish();
        }
      };
    })();
    """#
}

struct SafeHTMLNoteView: UIViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(HTMLNoteSecurity.readerDocument(bodyHTML: html), baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

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
    let url: URL
    let onAuthorizationExpired: () -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAuthorizationExpired: onAuthorizationExpired, onFailure: onFailure)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
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
    @Binding var html: String
    let command: HTMLNoteCommand?
    let commandToken: Int

    func makeCoordinator() -> Coordinator { Coordinator(html: $html) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: HTMLNoteSecurity.editorUserScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )
        configuration.userContentController.add(context.coordinator, name: "noteHTMLChanged")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.loadHTMLString(HTMLNoteSecurity.editorDocument(), baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.binding = $html
        if context.coordinator.isReady,
           context.coordinator.lastHTML != html {
            context.coordinator.setHTML(html)
        } else {
            context.coordinator.pendingHTML = html
        }

        guard commandToken != context.coordinator.lastCommandToken, let command else { return }
        context.coordinator.lastCommandToken = commandToken
        let arguments = command.javascriptArguments
        let commandJSON = Self.javascriptString(arguments.command)
        let valueJSON = arguments.value.map(Self.javascriptString) ?? "null"
        webView.evaluateJavaScript("window.__notePatchEditor && window.__notePatchEditor.command(\(commandJSON), \(valueJSON));")
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "noteHTMLChanged")
        webView.navigationDelegate = nil
    }

    nonisolated private static func javascriptString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(encoded.dropFirst().dropLast())
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var binding: Binding<String>
        weak var webView: WKWebView?
        var pendingHTML: String
        var lastHTML: String
        var lastCommandToken = -1
        var isReady = false

        init(html: Binding<String>) {
            binding = html
            pendingHTML = html.wrappedValue
            lastHTML = html.wrappedValue
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

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "noteHTMLChanged", let html = message.body as? String else { return }
            lastHTML = html
            if binding.wrappedValue != html {
                binding.wrappedValue = html
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
