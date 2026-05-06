import ObservationBridge

#if canImport(UIKit)
import UIKit

@MainActor
final class MiniPresetListViewController: UICollectionViewController {
    private let model: MiniContentViewModel
    private let observations = ObservationScope()
    private var dataSource: UICollectionViewDiffableDataSource<String, String>!

    init(model: MiniContentViewModel) {
        self.model = model
        super.init(collectionViewLayout: Self.makeLayout())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Languages"
        collectionView.allowsMultipleSelection = false
        dataSource = makeDataSource()
        applySnapshot()
        bindModel()
        renderSelection()
    }

    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let rawPresetID = dataSource.itemIdentifier(for: indexPath),
              let presetID = MiniPreviewPreset.ID(rawValue: rawPresetID)
        else {
            return
        }
        model.selectedPresetID = presetID
    }

    private func bindModel() {
        observations.update {
            model.observe(\.currentPresetID) { [weak self] _ in
                self?.renderSelection()
            }
            .store(in: observations)
        }
    }

    private func makeDataSource() -> UICollectionViewDiffableDataSource<String, String> {
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewListCell, String> {
            cell,
            _,
            rawPresetID in
            let presetID = MiniPreviewPreset.ID(rawValue: rawPresetID) ?? .javascript
            let preset = MiniPreviewPreset.preset(for: presetID) ?? .javascript
            var content = cell.defaultContentConfiguration()
            content.text = preset.title
            cell.contentConfiguration = content
            cell.accessibilityIdentifier = preset.accessibilityIdentifier
        }

        return UICollectionViewDiffableDataSource(collectionView: collectionView) {
            collectionView,
            indexPath,
            presetID in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: presetID
            )
        }
    }

    private func applySnapshot() {
        var snapshot = NSDiffableDataSourceSnapshot<String, String>()
        snapshot.appendSections([Self.sectionIdentifier])
        snapshot.appendItems(
            MiniPreviewPreset.all.map { $0.id.rawValue },
            toSection: Self.sectionIdentifier
        )
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    private func renderSelection() {
        collectionView.indexPathsForSelectedItems?.forEach {
            collectionView.deselectItem(at: $0, animated: false)
        }

        guard let indexPath = dataSource.indexPath(for: model.currentPresetID.rawValue) else {
            return
        }

        collectionView.selectItem(
            at: indexPath,
            animated: false,
            scrollPosition: []
        )
    }

    private static func makeLayout() -> UICollectionViewLayout {
        var configuration = UICollectionLayoutListConfiguration(appearance: .sidebar)
        configuration.showsSeparators = false
        return UICollectionViewCompositionalLayout.list(using: configuration)
    }

    private static let sectionIdentifier = "main"
}
#elseif canImport(AppKit)
import AppKit

@MainActor
final class MiniPresetListViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private let model: MiniContentViewModel
    private let observations = ObservationScope()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    init(model: MiniContentViewModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        title = "Languages"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        tableView.addTableColumn(NSTableColumn(identifier: .presetColumn))
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        bindModel()
        renderSelection()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        MiniPreviewPreset.all.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard MiniPreviewPreset.all.indices.contains(row) else { return nil }

        let preset = MiniPreviewPreset.all[row]
        let cell = tableView.makeView(withIdentifier: .presetCell, owner: self) as? NSTableCellView
            ?? makePresetCell()
        cell.textField?.stringValue = preset.title
        cell.setAccessibilityIdentifier(preset.accessibilityIdentifier)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = tableView.selectedRow
        guard MiniPreviewPreset.all.indices.contains(selectedRow) else { return }
        model.selectedPresetID = MiniPreviewPreset.all[selectedRow].id
    }

    private func bindModel() {
        observations.update {
            model.observe(\.currentPresetID) { [weak self] _ in
                self?.renderSelection()
            }
            .store(in: observations)
        }
    }

    private func renderSelection() {
        tableView.reloadData()

        guard let selectedIndex = MiniPreviewPreset.all.firstIndex(where: { $0.id == model.currentPresetID }) else {
            tableView.deselectAll(nil)
            return
        }

        tableView.selectRowIndexes(IndexSet(integer: selectedIndex), byExtendingSelection: false)
    }

    private func makePresetCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = .presetCell

        let textField = NSTextField(labelWithString: "")
        textField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(textField)
        cell.textField = textField

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let presetColumn = NSUserInterfaceItemIdentifier("PresetColumn")
    static let presetCell = NSUserInterfaceItemIdentifier("PresetCell")
}
#endif
