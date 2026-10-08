import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, en, ptBR = "pt-BR", pl
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return L.text("Idioma do Mac")
        case .en: return "English"
        case .ptBR: return "Português do Brasil"
        case .pl: return "Polski"
        }
    }
    static func resolve(_ choice: String, preferred: [String]) -> AppLanguage {
        if let explicit = AppLanguage(rawValue: choice), explicit != .system { return explicit }
        for language in preferred {
            switch language.lowercased().split(separator: "-").first {
            case "pt": return .ptBR
            case "pl": return .pl
            case "en": return .en
            default: continue
            }
        }
        return .en
    }
}
enum L {
    static var language: AppLanguage {
        AppLanguage.resolve(UserDefaults.standard.string(forKey: "appLanguage") ?? "system", preferred: Locale.preferredLanguages)
    }
    static let translations: [String: [String]] = {
        guard let url = Bundle.main.url(forResource: "Translations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return result
    }()
    static func text(_ key: String, language: AppLanguage? = nil) -> String {
        let selected = language ?? self.language
        guard selected != .ptBR, let values = translations[key], values.count == 2 else { return key }
        return values[selected == .pl ? 1 : 0]
    }
    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: language.rawValue), arguments: args)
    }
}
