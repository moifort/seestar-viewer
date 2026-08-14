import CoreGraphics
import SwiftUI

/// Range des éléments côte à côte, et revient à la ligne quand la largeur
/// manque.
///
/// `HStack` ne sait pas revenir à la ligne : quand la barre de télémétrie est
/// plus large que l'écran, il comprime chaque texte jusqu'à l'empiler lettre
/// par lettre. Ici les éléments gardent leur largeur naturelle, et c'est la
/// barre qui prend une ligne de plus.
struct FlowLayout: Layout {
    /// Espace entre deux éléments d'une même ligne.
    var spacing: CGFloat
    /// Espace entre deux lignes.
    var lineSpacing: CGFloat

    /// Découpe la suite des largeurs en lignes, dans l'ordre.
    ///
    /// Un élément plus large que la place disponible occupe malgré tout une
    /// ligne à lui seul : mieux vaut le voir déborder que le voir disparaître.
    static func rows(of widths: [CGFloat], spacing: CGFloat,
                     available: CGFloat) -> [[Int]] {
        // Les largeurs mesurées par SwiftUI sont fractionnaires : sans cette
        // tolérance, un contenu qui tient au point près partirait à la ligne
        // pour une erreur d'arrondi.
        let tolerance: CGFloat = 0.5
        var rows: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0

        for (index, width) in widths.enumerated() {
            if current.isEmpty {
                current = [index]
                used = width
            } else if used + spacing + width <= available + tolerance {
                current.append(index)
                used += spacing + width
            } else {
                rows.append(current)
                current = [index]
                used = width
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout Void) -> CGSize {
        let sizes = naturalSizes(subviews)
        // Sans proposition de largeur, la barre s'étend : c'est le cas du
        // téléviseur, où tout tient sur une ligne.
        let rows = Self.rows(of: sizes.map(\.width), spacing: spacing,
                             available: proposal.width ?? .infinity)
        let heights = rows.map { rowHeight($0, sizes) }
        return CGSize(
            width: rows.map { width($0, sizes) }.max() ?? 0,
            height: heights.reduce(0, +)
                + lineSpacing * CGFloat(max(rows.count - 1, 0))
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout Void) {
        let sizes = naturalSizes(subviews)
        let rows = Self.rows(of: sizes.map(\.width), spacing: spacing,
                             available: bounds.width)
        var y = bounds.minY

        for row in rows {
            let height = rowHeight(row, sizes)
            // Chaque ligne est centrée : une dernière ligne à demi remplie et
            // collée à gauche déséquilibrerait la barre.
            var x = bounds.minX + (bounds.width - width(row, sizes)) / 2
            for index in row {
                subviews[index].place(
                    at: CGPoint(x: x, y: y + height / 2),
                    anchor: .leading,
                    proposal: ProposedViewSize(sizes[index])
                )
                x += sizes[index].width + spacing
            }
            y += height + lineSpacing
        }
    }

    /// La taille que chaque élément prend quand rien ne le contraint : c'est
    /// elle qu'on veut respecter, plutôt que de comprimer les textes.
    private func naturalSizes(_ subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }

    private func width(_ row: [Int], _ sizes: [CGSize]) -> CGFloat {
        row.reduce(0) { $0 + sizes[$1].width }
            + spacing * CGFloat(max(row.count - 1, 0))
    }

    private func rowHeight(_ row: [Int], _ sizes: [CGSize]) -> CGFloat {
        row.map { sizes[$0].height }.max() ?? 0
    }
}
