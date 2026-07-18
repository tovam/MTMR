import AppKit

class ScrollViewItem: NSCustomTouchBarItem/*, NSGestureRecognizerDelegate*/ {

    init(identifier: NSTouchBarItem.Identifier, items: [NSTouchBarItem]) {
        super.init(identifier: identifier)
        let views = items.compactMap { $0.view }
        let stackView = NSStackView(views: views)
        stackView.spacing = 1
        stackView.orientation = .horizontal
        let contentSize = stackView.fittingSize
        let scrollView = NSScrollView(frame: CGRect(origin: .zero, size: contentSize))
        scrollView.documentView = stackView
        let naturalWidth = scrollView.widthAnchor.constraint(equalToConstant: contentSize.width)
        naturalWidth.priority = .defaultHigh
        naturalWidth.isActive = true
        view = scrollView
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
