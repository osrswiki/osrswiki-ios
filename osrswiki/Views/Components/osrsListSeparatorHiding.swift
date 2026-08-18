import SwiftUI
import UIKit

/// iOS 26 List is a UICollectionView compositional list. SwiftUI's
/// `.listRowSeparator(.hidden)` leaves the hairline in place, so walk the
/// hosting views and disable both UITableView and UICollectionViewListCell
/// separators after the list is in the tree.
struct osrsListSeparatorEraser: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            Self.strip(from: uiView)
        }
    }

    private static func strip(from view: UIView) {
        var node: UIView? = view
        while let current = node {
            if let table = current as? UITableView {
                table.separatorStyle = .none
                table.separatorColor = .clear
                table.separatorInset = .zero
            }
            if let collection = current as? UICollectionView {
                hideCollectionSeparators(in: collection)
            }
            if let cell = current as? UICollectionViewListCell {
                hideListCellSeparator(cell)
            }
            node = current.superview
        }
    }

    private static func hideCollectionSeparators(in collection: UICollectionView) {
        for cell in collection.visibleCells {
            if let listCell = cell as? UICollectionViewListCell {
                hideListCellSeparator(listCell)
            }
        }
        for subview in collection.subviews where subview.bounds.height <= 1 && subview.bounds.width > 8 {
            if subview.backgroundColor != nil && !(subview is UICollectionReusableView) {
                subview.backgroundColor = .clear
                subview.isHidden = true
            }
        }
    }

    private static func hideListCellSeparator(_ cell: UICollectionViewListCell) {
        cell.separatorLayoutGuide.widthAnchor.constraint(equalToConstant: 0).isActive = true
        cell.accessories = cell.accessories.filter { accessory in
            String(describing: accessory).localizedCaseInsensitiveContains("separator") == false
        }
    }
}

extension View {
    func osrsHidesListSeparators() -> some View {
        self
            .listRowSeparator(.hidden, edges: .all)
            .listSectionSeparator(.hidden)
            .listRowSeparatorTint(.clear)
            .listSectionSeparatorTint(.clear)
            .background(osrsListSeparatorEraser())
    }
}
