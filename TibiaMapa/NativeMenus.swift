import AppKit

/// Keep the app-owned native menus in sync with the in-app language preference.
/// Service-provider entries remain under macOS control.
@MainActor
enum NativeMenus {
    static var observers: [NSObjectProtocol] = []
    static let titles: [[String]] = [
        ["Edit", "Editar", "Edycja"], ["View", "Visualizar", "Widok"],
        ["Window", "Janela", "Okno"], ["Help", "Ajuda", "Pomoc"],
        ["Services", "Serviços", "Usługi"], ["Undo", "Desfazer", "Cofnij"],
        ["Redo", "Refazer", "Ponów"], ["Cut", "Recortar", "Wytnij"],
        ["Copy", "Copiar", "Kopiuj"], ["Paste", "Colar", "Wklej"],
        ["Delete", "Apagar", "Usuń"], ["Select All", "Selecionar Tudo", "Zaznacz wszystko"],
        ["Minimize", "Minimizar", "Minimalizuj"], ["Zoom", "Zoom", "Powiększ"],
        ["Bring All to Front", "Trazer Todas para Frente", "Przenieś wszystkie na wierzch"],
        ["Close Window", "Fechar Janela", "Zamknij okno"],
        ["Enter Full Screen", "Entrar em Tela Cheia", "Włącz pełny ekran"],
        ["Exit Full Screen", "Sair da Tela Cheia", "Wyłącz pełny ekran"],
        ["Show Sidebar", "Mostrar Barra Lateral", "Pokaż pasek boczny"],
        ["Hide Sidebar", "Ocultar Barra Lateral", "Ukryj pasek boczny"],
        ["Toggle Sidebar", "Alternar Barra Lateral", "Przełącz pasek boczny"],
        ["Show Toolbar", "Mostrar Barra de Ferramentas", "Pokaż pasek narzędzi"],
        ["Hide Toolbar", "Ocultar Barra de Ferramentas", "Ukryj pasek narzędzi"],
        ["Customize Toolbar…", "Personalizar Barra de Ferramentas…", "Dostosuj pasek narzędzi…"],
        ["About TibiaMapa", "Sobre o App TibiaMapa", "TibiaMapa — informacje"],
        ["Hide TibiaMapa", "Ocultar TibiaMapa", "Ukryj TibiaMapa"],
        ["Hide Others", "Ocultar Outros", "Ukryj pozostałe"],
        ["Show All", "Mostrar Tudo", "Pokaż wszystkie"],
        ["Quit TibiaMapa", "Encerrar TibiaMapa", "Zakończ TibiaMapa"],
        ["Quit and Keep Windows", "Encerrar e Manter as Janelas", "Zakończ i zachowaj okna"],
        ["TibiaMapa Help", "Ajuda do TibiaMapa", "Pomoc TibiaMapa"],
        ["Spelling and Grammar", "Ortografia e Gramática", "Pisownia i gramatyka"],
        ["Substitutions", "Substituições", "Zastępowanie"],
        ["Transformations", "Transformações", "Przekształcenia"],
        ["Speech", "Fala", "Mowa"],
        ["Start Dictation…", "Iniciar Ditado…", "Rozpocznij dyktowanie…"],
        ["Emoji & Symbols", "Emoji e Símbolos", "Emoji i symbole"]
    ]
    static func translated(_ title: String, language: AppLanguage) -> String {
        let index = language == .ptBR ? 1 : language == .pl ? 2 : 0
        return titles.first(where: { $0.contains(title) })?[index] ?? title
    }
    static func install() {
        guard observers.isEmpty else { update(); return }
        for name in [NSMenu.didAddItemNotification,
                     NSApplication.didBecomeActiveNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
                MainActor.assumeIsolated {
                    if notification.name == NSMenu.didAddItemNotification {
                        guard let menu = notification.object as? NSMenu, menu === NSApp.mainMenu else { return }
                    }
                    update()
                }
            })
        }
        DispatchQueue.main.async { update() }
    }
    static func simplify(_ menu: NSMenu) {
        for item in menu.items.dropFirst() {
            allowShortcuts(item)
            item.isHidden = true
        }
    }
    private static func allowShortcuts(_ item: NSMenuItem) {
        item.allowsKeyEquivalentWhenHidden = true
        item.submenu?.items.forEach(allowShortcuts)
    }
    static func update() {
        guard let menu = NSApp.mainMenu else { return }
        simplify(menu)
        apply(menu, language: L.language)
    }
    private static func apply(_ menu: NSMenu, language: AppLanguage) {
        for item in menu.items {
            let isServices = titles[4].contains(item.title)
            item.title = translated(item.title, language: language)
            if let child = item.submenu {
                child.title = translated(child.title, language: language)
                if !isServices { apply(child, language: language) }
            }
        }
    }
}
