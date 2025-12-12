import SwiftUI
import WebKit
import UIKit
import StoreKit

// MARK: -- Papyrus Display View

/// Конфигурация для отображения веб-контента папируса
public struct PapyrusDisplayView: UIViewRepresentable {
    let urlString: String
    let allowsGestures: Bool
    let enableRefresh: Bool
    
    public init(urlString: String, allowsGestures: Bool = true, enableRefresh: Bool = true) {
        self.urlString = urlString
        self.allowsGestures = allowsGestures
        self.enableRefresh = enableRefresh
    }
    
    public func makeUIView(context: Context) -> WKWebView {
        let pharaohConfig = WKWebViewConfiguration()
        let pharaohPreferences = WKWebpagePreferences()
        
        // Настройка JavaScript
        pharaohPreferences.allowsContentJavaScript = true
        pharaohConfig.defaultWebpagePreferences = pharaohPreferences
        pharaohConfig.preferences.javaScriptCanOpenWindowsAutomatically = true
        // Настройка медиа
        pharaohConfig.allowsInlineMediaPlayback = true
        pharaohConfig.mediaTypesRequiringUserActionForPlayback = []
        pharaohConfig.allowsAirPlayForMediaPlayback = true
        pharaohConfig.allowsPictureInPictureMediaPlayback = true
        
        // Настройка данных сайта
        pharaohConfig.websiteDataStore = WKWebsiteDataStore.default()
        
        // Создание WebView
        let pharaohView = WKWebView(frame: .zero, configuration: pharaohConfig)
        
        // Настройка фона (черный)
        pharaohView.backgroundColor = .black
        pharaohView.scrollView.backgroundColor = .black
        pharaohView.isOpaque = false
        
        // Настройка жестов
        pharaohView.allowsBackForwardNavigationGestures = allowsGestures
        
        // Используем Desktop Safari User Agent для прохождения Google OAuth
        // Desktop версия обходит блокировку "embedded browsers"
        pharaohView.customUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        
        // Настройка координатора
        pharaohView.navigationDelegate = context.coordinator
        pharaohView.uiDelegate = context.coordinator
        
        // Настройка refresh control
        let pharaohRefreshControl = UIRefreshControl()
        pharaohRefreshControl.tintColor = .white
        pharaohRefreshControl.addTarget(context.coordinator, action: #selector(context.coordinator.refreshPapyrus(_:)), for: .valueChanged)
        pharaohView.scrollView.refreshControl = pharaohRefreshControl
        
        // Сохраняем ссылки в координаторе
        context.coordinator.pharaohWebView = pharaohView
        context.coordinator.pharaohRefreshControl = pharaohRefreshControl
        
        if let url = URL(string: urlString) {
            pharaohView.load(URLRequest(url: url))
        }
        
        return pharaohView
    }
    
    public func updateUIView(_ uiView: WKWebView, context: Context) {
        // ⚠️ НЕ перезагружаем на каждый апдейт SwiftUI
        // Загружаем только если реально сменился URL
        if uiView.url?.absoluteString != urlString, let url = URL(string: urlString) {
            uiView.load(URLRequest(url: url))
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: -- Coordinator
    
    public class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: PapyrusDisplayView
        weak var pharaohWebView: WKWebView?
        weak var pharaohRefreshControl: UIRefreshControl?
        var oauthWebView: WKWebView? // Временный WebView для OAuth
        
        init(_ parent: PapyrusDisplayView) {
            self.parent = parent
            super.init()
            
            // Настройка observers для всех событий клавиатуры
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillShowPharaoh),
                name: UIResponder.keyboardWillShowNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardDidShowPharaoh),
                name: UIResponder.keyboardDidShowNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardWillHidePharaoh),
                name: UIResponder.keyboardWillHideNotification,
                object: nil
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(keyboardDidHidePharaoh),
                name: UIResponder.keyboardDidHideNotification,
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func refreshPapyrus(_ sender: UIRefreshControl) {
            pharaohWebView?.reload()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.pharaohRefreshControl?.endRefreshing()
            }
        }
        
        // MARK: - Keyboard Handling
        
        // Мягкий viewport refresh без изменения DOM
        private func softViewportRefreshPharaoh() {
            guard let pharaohWebView = pharaohWebView else { return }
            
            // Легкий JavaScript - только события, без изменения DOM
            let pharaohJavaScript = """
            (function() {
                // Триггер viewport и window resize событий
                if (window.visualViewport) {
                    window.dispatchEvent(new Event('resize'));
                }
                window.dispatchEvent(new Event('resize'));
                
                // Легкий scroll для триггера reflow
                window.scrollBy(0, 1);
                window.scrollBy(0, -1);
            })();
            """
            
            pharaohWebView.evaluateJavaScript(pharaohJavaScript, completionHandler: nil)
            
            // Легкий нативный scroll
            let currentOffset = pharaohWebView.scrollView.contentOffset
            pharaohWebView.scrollView.setContentOffset(
                CGPoint(x: currentOffset.x, y: currentOffset.y + 1),
                animated: false
            )
            pharaohWebView.scrollView.setContentOffset(currentOffset, animated: false)
        }
        
        @objc private func keyboardWillShowPharaoh(_ notification: Notification) {
            softViewportRefreshPharaoh()
        }
        
        @objc private func keyboardDidShowPharaoh(_ notification: Notification) {
            // Отложенный refresh после полного показа клавиатуры
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.softViewportRefreshPharaoh()
            }
        }
        
        @objc private func keyboardWillHidePharaoh(_ notification: Notification) {
            softViewportRefreshPharaoh()
        }
        
        @objc private func keyboardDidHidePharaoh(_ notification: Notification) {
            // Немедленный refresh
            softViewportRefreshPharaoh()
            
            // Вторая попытка после задержки
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.softViewportRefreshPharaoh()
            }
            
            // Третья попытка после длинной задержки для упорных случаев
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.softViewportRefreshPharaoh()
            }
        }
        
        // MARK: - Navigation Handling
        
        // Обработка навигации
        public func webView(_ webView: WKWebView,
                            decidePolicyFor action: WKNavigationAction,
                            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            
            if let url = action.request.url {
                let urlString = url.absoluteString
                
                // Если это временный WebView - перехватываем РЕАЛЬНЫЙ URL здесь!
                if webView == oauthWebView {
                    if !urlString.isEmpty && 
                       urlString != "about:blank" &&
                       !urlString.hasPrefix("about:") {
                        // Загружаем в основной WebView
                        if let mainWebView = pharaohWebView {
                            mainWebView.load(URLRequest(url: url))
                            oauthWebView = nil
                        }
                        decisionHandler(.cancel)
                        return
                    }
                }
                
                let scheme = url.scheme?.lowercased()
                
                // Открываем внешние схемы в системе
                if let scheme = scheme,
                   scheme != "http", scheme != "https", scheme != "about" {
                    UIApplication.shared.open(url, options: [:], completionHandler: nil)
                    decisionHandler(.cancel)
                    return
                }
                
                // OAuth popup - загружаем в том же WebView (со свайпом назад)
                if action.targetFrame == nil {
                    webView.load(URLRequest(url: url))
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
        
        // Обработка дочерних окон - перехватываем URL для основного WebView
        public func webView(_ webView: WKWebView,
                            createWebViewWith configuration: WKWebViewConfiguration,
                            for navAction: WKNavigationAction,
                            windowFeatures: WKWindowFeatures) -> WKWebView? {
            
            // Если URL есть - загружаем в текущий WebView
            if let url = navAction.request.url, 
               !url.absoluteString.isEmpty,
               url.absoluteString != "about:blank" {
                webView.load(URLRequest(url: url))
                return nil
            }
            
            // Если URL пустой - создаем СКРЫТЫЙ временный WebView
            // Он перехватит URL, который загрузит JavaScript, и передаст в основной WebView
            let tempView = WKWebView(frame: .zero, configuration: configuration)
            tempView.navigationDelegate = self
            tempView.uiDelegate = self
            tempView.isHidden = true
            
            self.oauthWebView = tempView
            return tempView
        }
        
        // Закрытие временного WebView
        public func webViewDidClose(_ webView: WKWebView) {
            if webView == oauthWebView {
                oauthWebView = nil
            }
        }
        
        // Обработка начала навигации
        public func webView(_ pharaohWebView: WKWebView, didStartProvisionalNavigation pharaohNavigation: WKNavigation!) {
            // Если это временный WebView - перехватываем РЕАЛЬНЫЙ URL (не about:blank)
            if pharaohWebView == oauthWebView, let realUrl = pharaohWebView.url {
                let urlString = realUrl.absoluteString
                
                // Игнорируем пустые URL и about:blank
                if !urlString.isEmpty && 
                   urlString != "about:blank" &&
                   !urlString.hasPrefix("about:") {
                    // Загружаем в основной WebView
                    if let mainWebView = self.pharaohWebView {
                        mainWebView.load(URLRequest(url: realUrl))
                        oauthWebView = nil
                    }
                    return
                }
            }
        }
        
        // Обработка завершения загрузки
        public func webView(_ pharaohWebView: WKWebView, didFinish pharaohNavigation: WKNavigation!) {
            pharaohRefreshControl?.endRefreshing()
        }
        
        // Обработка ошибок загрузки
        public func webView(_ pharaohWebView: WKWebView, didFail pharaohNavigation: WKNavigation!, withError pharaohError: Error) {
            pharaohRefreshControl?.endRefreshing()
        }
        
        // Обработка ошибок загрузки (провизорная навигация)
        public func webView(_ pharaohWebView: WKWebView, didFailProvisionalNavigation pharaohNavigation: WKNavigation!, withError pharaohError: Error) {
            // Обработка ошибок
        }
    }
}

// MARK: -- Safe Papyrus Display View

/// SwiftUI обертка для PapyrusDisplayView с отступами от safe area
public struct SafePapyrusDisplayView: View {
    let urlString: String
    let allowsGestures: Bool
    let enableRefresh: Bool
    
    public init(urlString: String, allowsGestures: Bool = true, enableRefresh: Bool = true) {
        self.urlString = urlString
        self.allowsGestures = allowsGestures
        self.enableRefresh = enableRefresh
    }
    
    public var body: some View {
        ZStack {
            // Черный фон
            Color.black
                .ignoresSafeArea()
            
            // WebView с отступами от safe area
            PapyrusDisplayView(
                urlString: urlString,
                allowsGestures: allowsGestures,
                enableRefresh: enableRefresh
            )
            .ignoresSafeArea(.keyboard)
            .onAppear {
               
                
                // Запрос оценки при третьем запуске
                let launchCount = UserDefaults.standard.integer(forKey: "animationGalaxyLaunchCount")
                if launchCount == 2 {
                    if let scene = UIApplication.shared
                        .connectedScenes
                        .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                        SKStoreReviewController.requestReview(in: scene)
                    }
                }
            }
        }
    }
}

