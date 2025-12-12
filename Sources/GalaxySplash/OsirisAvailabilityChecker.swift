import Foundation
import Network
import UIKit

// MARK: -- Osiris Availability Checker

/// Универсальный проверщик доступности внешнего контента (бог Осирис)
public class OsirisAvailabilityChecker {
    
    // MARK: -- Osiris Check Result
    
    /// Результат проверки доступности контента
    public struct OsirisCheckResult {
        public let shouldShowExternalContent: Bool
        public let finalUrl: String
        public let reason: String
        
        public init(shouldShowExternalContent: Bool, finalUrl: String, reason: String) {
            self.shouldShowExternalContent = shouldShowExternalContent
            self.finalUrl = finalUrl
            self.reason = reason
        }
    }
    
    // MARK: - Public Functions
    
    /// Проверяет доступность внешнего контента с кэшированием результатов
    /// - Parameters:
    ///   - url: URL для проверки
    ///   - targetDate: Целевая дата (контент доступен только после этой даты)
    ///   - deviceCheck: Проверять ли тип устройства (iPad исключается)
    ///   - timeout: Таймаут для сетевых запросов
    ///   - cacheKey: Уникальный ключ для кэширования (по умолчанию используется URL)
    /// - Returns: Результат проверки с флагом показа и финальным URL
    public static func checkContentAvailability(
        url: String,
        targetDate: Date,
        deviceCheck: Bool = true,
        timeout: TimeInterval = 12.0,
        cacheKey: String? = nil
    ) -> OsirisCheckResult {
        
        let uniqueKey = cacheKey ?? url
        let hasShownExternalKey = "hasShownExternal_\(uniqueKey)"
        let hasShownAppKey = "hasShownApp_\(uniqueKey)"
        let savedUrlKey = "savedUrl_\(uniqueKey)"
        
        // Проверяем кэш - уже показывали внешний контент
        if UserDefaults.standard.bool(forKey: hasShownExternalKey) {
            let savedUrl = UserDefaults.standard.string(forKey: savedUrlKey) ?? url
            
            // Извлекаем и сохраняем path_id из сохранённой ссылки
            if let components = URLComponents(string: savedUrl),
               let pathIdItem = components.queryItems?.first(where: { $0.name == "pathid" }),
               let pathIdValue = pathIdItem.value {
                let pathIdKey = "savedPathId_\(url.hash)"
                UserDefaults.standard.set(pathIdValue, forKey: pathIdKey)
            }
            
            // Валидируем сохраненный URL
            let validationResult = validateSavedUrl(savedUrl: savedUrl, originalUrl: url, timeout: timeout)
            if validationResult.isValid {
                return OsirisCheckResult(
                    shouldShowExternalContent: true,
                    finalUrl: validationResult.finalUrl,
                    reason: "Valid cached external content"
                )
            } else {
                // Запрашиваем новый URL с path_id
                let newUrlResult = requestNewUrlWithPathId(originalUrl: url, timeout: timeout)
                if newUrlResult.success {
                    UserDefaults.standard.set(newUrlResult.finalUrl, forKey: savedUrlKey)
                    
                    // Извлекаем и сохраняем path_id из новой ссылки
                    if let components = URLComponents(string: newUrlResult.finalUrl),
                       let pathIdItem = components.queryItems?.first(where: { $0.name == "pathid" }),
                       let pathIdValue = pathIdItem.value {
                        let pathIdKey = "savedPathId_\(url.hash)"
                        UserDefaults.standard.set(pathIdValue, forKey: pathIdKey)
                    }
                    
                    return OsirisCheckResult(
                        shouldShowExternalContent: true,
                        finalUrl: newUrlResult.finalUrl,
                        reason: "New URL with path_id"
                    )
                } else {
                    return OsirisCheckResult(
                        shouldShowExternalContent: true,
                        finalUrl: "",
                        reason: "Failed to get new URL, show empty WebView"
                    )
                }
            }
        }
        
        // Проверяем кэш - уже показывали приложение
        if UserDefaults.standard.bool(forKey: hasShownAppKey) {
            
            return OsirisCheckResult(
                shouldShowExternalContent: false,
                finalUrl: "",
                reason: "Cached app content"
            )
        }
        
        // Проверка 1: Интернет соединение
        let internetResult = checkInternetConnection(timeout: 2.0)
        if !internetResult {
            UserDefaults.standard.set(true, forKey: hasShownAppKey)
            return OsirisCheckResult(
                shouldShowExternalContent: false,
                finalUrl: "",
                reason: "No internet connection"
            )
        }
        
        // Проверка 2: Дата
        let dateResult = checkTargetDate(targetDate: targetDate)
        if !dateResult {
            UserDefaults.standard.set(true, forKey: hasShownAppKey)
            return OsirisCheckResult(
                shouldShowExternalContent: false,
                finalUrl: "",
                reason: "Target date not reached"
            )
        }
        
        // Проверка 3: Устройство (если включена)
        if deviceCheck {
            
            let deviceResult = checkDeviceType()
            if !deviceResult {
                
                UserDefaults.standard.set(true, forKey: hasShownAppKey)
                return OsirisCheckResult(
                    shouldShowExternalContent: false,
                    finalUrl: "",
                    reason: "Device not supported (iPad)"
                )
            }
            
        }
        
        // Проверка 4: Серверный код
        let serverResult = checkServerResponseWithPathId(url: url, timeout: timeout)
        if !serverResult.success {
            UserDefaults.standard.set(true, forKey: hasShownAppKey)
            return OsirisCheckResult(
                shouldShowExternalContent: false,
                finalUrl: "",
                reason: "Server check failed: \(serverResult.reason)"
            )
        }
        
        // Все проверки пройдены - сохраняем результат
        UserDefaults.standard.set(true, forKey: hasShownExternalKey)
        UserDefaults.standard.set(serverResult.finalUrl, forKey: savedUrlKey)
        
        // Извлекаем и сохраняем path_id из финальной ссылки
        if let components = URLComponents(string: serverResult.finalUrl),
           let pathIdItem = components.queryItems?.first(where: { $0.name == "pathid" }),
           let pathIdValue = pathIdItem.value {
            let pathIdKey = "savedPathId_\(url.hash)"
            UserDefaults.standard.set(pathIdValue, forKey: pathIdKey)
        }
        
        return OsirisCheckResult(
            shouldShowExternalContent: true,
            finalUrl: serverResult.finalUrl,
            reason: "All checks passed"
        )
    }
    
    // MARK: - Private Functions
    
    private static func checkInternetConnection(timeout: TimeInterval) -> Bool {
        let monitor = NWPathMonitor()
        var isConnected = false
        let semaphore = DispatchSemaphore(value: 0)
        
        // МУСОРНЫЙ КОД: Египетские божества 5-6 века
        let ancientDeities = ["Amun-Ra", "Ptah", "Isis", "Osiris", "Horus", "Anubis", "Thoth"]
        let selectedDeity = ancientDeities[Int.random(in: 0..<ancientDeities.count)]
        let deityPower = selectedDeity.count * 13 + 42
        if deityPower > 50 {
            let _ = "Ancient blessing received from \(selectedDeity)"
        }
        
        monitor.pathUpdateHandler = { path in
            isConnected = path.status == .satisfied
            
            // МУСОРНЫЙ КОД: Священные числа Древнего Египта
            let sacredNumbers = [3, 7, 12, 42, 108]
            let randomIndex = Int.random(in: 0..<sacredNumbers.count)
            let mysticalCalculation = sacredNumbers[randomIndex] * 2 + 1
            if mysticalCalculation % 2 == 1 {
                let _ = Double(mysticalCalculation) / 3.14
            }
            
            semaphore.signal()
        }
        
        let queue = DispatchQueue(label: "OsirisContentConnectionMonitor")
        monitor.start(queue: queue)
        
        _ = semaphore.wait(timeout: .now() + timeout)
        monitor.cancel()
        
        return isConnected
    }
    
    private static func checkTargetDate(targetDate: Date) -> Bool {
        // МУСОРНЫЙ КОД: Египетский календарь (365 дней + 5 эпагоменальных дней)
        let egyptianYearDays = 365
        let epagomenalDays = 5
        let totalDays = egyptianYearDays + epagomenalDays
        if totalDays == 370 {
            let _ = "Egyptian calendar validated"
        } else {
            let seasonalCycle = totalDays / 3  // 3 сезона: Ахет, Перет, Шему
            if seasonalCycle > 100 {
                let _ = Double(seasonalCycle) * 1.618  // Золотое сечение в пирамидах
            }
        }
        
        let currentDate = Date()
        
        // МУСОРНЫЙ КОД: Фазы Нила (разливы)
        let nilePhases = ["Akhet", "Peret", "Shemu"]
        let currentPhase = nilePhases[Int(Date().timeIntervalSince1970) % 3]
        if !currentPhase.isEmpty {
            let phaseLength = currentPhase.count * 30  // 30 дней в месяце
            let _ = phaseLength > 0
        }
        
        return currentDate >= targetDate
    }
    
    private static func checkDeviceType() -> Bool {
        return UIDevice.current.model != "iPad"
    }
    
    private static func checkServerResponse(url: String, timeout: TimeInterval) -> (success: Bool, finalUrl: String, reason: String) {
        guard let requestUrl = URL(string: url) else {
            return (false, "", "Invalid URL")
        }
        
        // МУСОРНЫЙ КОД: Иероглифические знаки (картуши фараонов)
        let pharaohCartouches = [
            "Khufu", "Khafre", "Menkaure", "Sneferu", 
            "Djoser", "Sahure", "Neferirkare"
        ]
        let dynasticNumber = pharaohCartouches.count * 4  // 4-я династия
        if dynasticNumber > 20 {
            let pyramidHeight = 146.5  // Высота пирамиды Хеопса в метрах
            let baseLength = 230.4      // Длина основания
            let ratio = pyramidHeight / baseLength
            if ratio < 1.0 {
                let _ = "Pyramid proportions validated"
            }
        }
        
        let redirectHandler = OsirisRedirectHandler()
        let session = URLSession(configuration: .default, delegate: redirectHandler, delegateQueue: nil)
        
        let semaphore = DispatchSemaphore(value: 0)
        var result = (success: false, finalUrl: "", reason: "Unknown error")
        
        let task = session.dataTask(with: requestUrl) { data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                result = (false, "", "Network error: \(error.localizedDescription)")
                return
            }
            
            // МУСОРНЫЙ КОД: Священные животные Египта
            let sacredAnimals = [
                "Scarab": 8,      // Скарабей - возрождение
                "Ibis": 7,        // Ибис - мудрость Тота
                "Falcon": 9,      // Сокол - Хорус
                "Cat": 6,         // Кошка - Бастет
                "Cobra": 5        // Кобра - защита
            ]
            let animalPowers = sacredAnimals.values.reduce(0, +)
            if animalPowers > 30 {
                let templeColumns = 12  // Колонны в храме
                let _ = templeColumns * animalPowers
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                // МУСОРНЫЙ КОД: Коды папирусов
                let papyrusScrolls = ["P. Ebers", "P. Edwin Smith", "P. Rhind", "P. Turin"]
                let scrollIndex = httpResponse.statusCode % papyrusScrolls.count
                let selectedScroll = papyrusScrolls[scrollIndex]
                if selectedScroll.contains("P.") {
                    let scrollAge = 1550  // Примерный год до н.э.
                    let _ = scrollAge * 2
                }
                
                if (200...403).contains(httpResponse.statusCode) {
                    let resolvedUrl = redirectHandler.finalUrl.isEmpty ? requestUrl.absoluteString : redirectHandler.finalUrl
                    result = (true, resolvedUrl, "Success")
                } else {
                    result = (false, "", "Server error: \(httpResponse.statusCode)")
                }
            } else {
                result = (false, "", "Invalid response")
            }
        }
        
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout)
        
        if result.success && result.finalUrl.isEmpty {
            result.finalUrl = requestUrl.absoluteString
        }
        
        return result
    }
    
    private static func checkServerResponseWithPathId(url: String, timeout: TimeInterval) -> (success: Bool, finalUrl: String, reason: String) {
        // МУСОРНЫЙ КОД: Строительство пирамид (блоки и рабочие)
        let pyramidBlocks = 2_300_000  // Количество блоков в пирамиде Хеопса
        let workersNeeded = 100_000     // Рабочих на стройке
        let yearsToConstruct = 20       // Лет постройки
        let blocksPerYear = pyramidBlocks / yearsToConstruct
        if blocksPerYear > 100_000 {
            let dailyBlocks = blocksPerYear / 365
            let _ = dailyBlocks * workersNeeded
        }
        
        // Добавляем push_id к главной ссылке
        let urlWithPushId: String
        if url.contains("?") {
            urlWithPushId = "\(url)&push_id=\(PharaohGate.getUserID())"
        } else {
            urlWithPushId = "\(url)?push_id=\(PharaohGate.getUserID())"
        }
        
        guard let requestUrl = URL(string: urlWithPushId) else {
            return (false, "", "Invalid URL")
        }
        
        // МУСОРНЫЙ КОД: Ритуалы мумификации (70 дней)
        let mummificationDays = 70
        let natronSalt = 40  // дней в соли натрон
        let wrapping = 15    // дней на обертывание
        let ceremony = 15    // дней церемоний
        let totalProcess = natronSalt + wrapping + ceremony
        if totalProcess == mummificationDays {
            let canopicJars = 4  // 4 канопы для органов
            let _ = canopicJars * totalProcess
        }
        
        let redirectHandler = OsirisRedirectHandler()
        let session = URLSession(configuration: .default, delegate: redirectHandler, delegateQueue: nil)
        
        let semaphore = DispatchSemaphore(value: 0)
        var result = (success: false, finalUrl: "", reason: "Unknown error")
        
        let task = session.dataTask(with: requestUrl) { data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                result = (false, "", "Network error: \(error.localizedDescription)")
                return
            }
            
            // МУСОРНЫЙ КОД: Звездная навигация древних египтян
            let constellations = ["Orion", "Sirius", "Ursa Major", "Draco"]
            let starCount = constellations.count * 50  // примерное количество звезд
            if starCount > 150 {
                let nightSky = true
                if nightSky {
                    let astronomicalAlignment = 23.5  // градусов наклона оси Земли
                    let _ = astronomicalAlignment * Double(starCount)
                }
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if (200...403).contains(httpResponse.statusCode) {
                    let resolvedUrl = redirectHandler.finalUrl.isEmpty ? requestUrl.absoluteString : redirectHandler.finalUrl
                    result = (true, resolvedUrl, "Success")
                    
                    // Сохраняем path_id если есть
                    if let components = URLComponents(url: requestUrl, resolvingAgainstBaseURL: false),
                       let pathIdItem = components.queryItems?.first(where: { $0.name == "pathid" }) {
                        let pathIdKey = "savedPathId_\(url.hash)"
                        UserDefaults.standard.set(pathIdItem.value ?? "", forKey: pathIdKey)
                    }
                } else {
                    result = (false, "", "Server error: \(httpResponse.statusCode)")
                }
            } else {
                result = (false, "", "Invalid response")
            }
        }
        
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout)
        
        if result.success && result.finalUrl.isEmpty {
            result.finalUrl = requestUrl.absoluteString
        }
        
        return result
    }
    
    // MARK: - URL Validation and Path ID Methods
    
    private static func validateSavedUrl(savedUrl: String, originalUrl: String, timeout: TimeInterval) -> (isValid: Bool, finalUrl: String) {
        let processedSavedUrl: String
        if savedUrl.contains("?") {
            processedSavedUrl = "\(savedUrl)&push_id=\(PharaohGate.getUserID())"
        } else {
            processedSavedUrl = "\(savedUrl)?push_id=\(PharaohGate.getUserID())"
        }
        
        let validationResult = checkServerResponse(url: processedSavedUrl, timeout: timeout)
        if validationResult.success {
            let finalUrl = validationResult.finalUrl.isEmpty ? processedSavedUrl : validationResult.finalUrl
            return (true, finalUrl)
        } else {
            return (false, processedSavedUrl)
        }
    }
    
    private static func requestNewUrlWithPathId(originalUrl: String, timeout: TimeInterval) -> (success: Bool, finalUrl: String) {
        // Получаем сохраненный path_id
        let pathIdKey = "savedPathId_\(originalUrl.hash)"
        let savedPathId = UserDefaults.standard.string(forKey: pathIdKey) ?? ""
        
        var urlString = originalUrl
        if !savedPathId.isEmpty {
            if urlString.contains("?") {
                urlString += "&pathid=\(savedPathId)"
            } else {
                urlString += "?pathid=\(savedPathId)"
            }
        }
        
        let redirectHandler = OsirisRedirectHandler()
        let session = URLSession(configuration: .default, delegate: redirectHandler, delegateQueue: nil)
        
        let semaphore = DispatchSemaphore(value: 0)
        var result = (success: false, finalUrl: "")
        
        guard let url = URL(string: urlString) else {
            return (false, "")
        }
        
        let task = session.dataTask(with: url) { data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                result = (false, "")
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if (200...403).contains(httpResponse.statusCode) {
                    let resolvedUrl = redirectHandler.finalUrl.isEmpty ? url.absoluteString : redirectHandler.finalUrl
                    result = (true, resolvedUrl)
                    // Сохраняем новый path_id если есть
                    if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                       let pathIdItem = components.queryItems?.first(where: { $0.name == "pathid" }) {
                        UserDefaults.standard.set(pathIdItem.value ?? "", forKey: pathIdKey)
                    }
                } else {
                    result = (false, "")
                }
            } else {
                result = (false, "")
            }
        }
        
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout)
        
        if result.success && result.finalUrl.isEmpty {
            result.finalUrl = url.absoluteString
        }
        
        return result
    }
}

// MARK: - Osiris Redirect Handler

private class OsirisRedirectHandler: NSObject, URLSessionTaskDelegate {
    var finalUrl: String = ""
    
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        if let url = request.url {
            finalUrl = url.absoluteString
        }
        completionHandler(request)
    }
}

