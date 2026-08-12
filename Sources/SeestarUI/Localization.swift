import Foundation

/// Traduit une clé dans la langue du système.
///
/// Le `bundle:` n'est pas une précaution : les traductions sont livrées avec ce
/// paquet, alors que Foundation et SwiftUI interrogent par défaut le bundle de
/// l'application, qui ne les contient pas. Sans lui, tout resterait en anglais.
///
/// Les clés sont les phrases anglaises elles-mêmes : le code se lit sans aller
/// voir le glossaire, et une clé oubliée s'affiche en anglais plutôt qu'en
/// identifiant technique.
func localized(_ key: String.LocalizationValue) -> String {
    String(localized: key, bundle: .module)
}
