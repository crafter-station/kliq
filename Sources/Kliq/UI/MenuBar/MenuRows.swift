import AppKit

/// Geometry shared by the custom menu rows, measured against native items: titles and
/// item images start after the checkmark column, 24 pt in, and key equivalents end
/// 14 pt from the right edge, where separators end too.
enum MenuMetrics {
    static let width: CGFloat = 276
    static let leading: CGFloat = 24
    static let trailing: CGFloat = 14
}

/// The top row: app name, live state and the switch that turns sounds on and off.
final class MenuHeaderView: NSView {
    let toggle = NSSwitch()
    private let status = NSTextField(labelWithString: "")

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: 44))
        autoresizingMask = .width

        let title = NSTextField(labelWithString: "Kliq")
        title.font = .systemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold)
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        // VoiceOver reads the switch as "Kliq", so the label itself is skipped.
        title.setAccessibilityElement(false)
        status.setAccessibilityElement(false)

        toggle.controlSize = .mini
        toggle.setAccessibilityLabel("Kliq")

        for view in [title, status, toggle] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuMetrics.leading),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            status.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            status.topAnchor.constraint(equalTo: title.bottomAnchor, constant: -1),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuMetrics.trailing),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var statusText: String {
        get { status.stringValue }
        set {
            status.stringValue = newValue
            toggle.setAccessibilityHelp(newValue)
        }
    }
}

/// A line of secondary text with a small button, shown under the header while Kliq
/// needs attention, such as "Sleeping · microphone in use" with Wake.
final class MenuNoticeView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")
    let button: NSButton
    private static let padding: CGFloat = 4
    private static let spacing: CGFloat = 8

    init(buttonTitle: String) {
        button = NSButton(title: buttonTitle, target: nil, action: nil)
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: 28))
        autoresizingMask = .width

        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 2
        label.cell?.truncatesLastVisibleLine = true
        button.bezelStyle = .push
        button.controlSize = .small
        button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        label.preferredMaxLayoutWidth = MenuMetrics.width - MenuMetrics.leading - MenuMetrics.trailing
            - button.fittingSize.width - Self.spacing

        for view in [label, button] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuMetrics.leading),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -Self.spacing),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuMetrics.trailing),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Sets the text and sizes the row to fit it on up to two lines.
    var text: String {
        get { label.stringValue }
        set {
            guard newValue != label.stringValue else { return }
            label.stringValue = newValue
            let height = (max(label.fittingSize.height, button.fittingSize.height) + Self.padding * 2).rounded(.up)
            guard height != frame.height else { return }
            setFrameSize(NSSize(width: frame.width, height: height))
            // An open menu keeps a row's height until the item is handed its view again.
            if let item = enclosingMenuItem {
                item.view = nil
                item.view = self
            }
        }
    }
}

/// A full-width slider aligned with the item titles.
final class MenuSliderView: NSView {
    let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let valueLabel = NSTextField(labelWithString: "0%")

    init(accessibilityLabel: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: MenuMetrics.width, height: 28))
        autoresizingMask = .width

        let icon = NSImageView(image: NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)!)
        icon.contentTintColor = .secondaryLabelColor
        icon.setAccessibilityElement(false)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.setAccessibilityLabel(accessibilityLabel)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.setAccessibilityElement(false)
        for view in [icon, slider, valueLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: MenuMetrics.leading),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 13),
            slider.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            slider.trailingAnchor.constraint(equalTo: valueLabel.leadingAnchor, constant: -8),
            slider.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -MenuMetrics.trailing),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            valueLabel.widthAnchor.constraint(equalToConstant: 34),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    var doubleValue: Double {
        get { slider.doubleValue }
        set {
            slider.doubleValue = newValue
            updateReadout()
        }
    }

    func updateReadout() {
        valueLabel.stringValue = "\(Int((slider.doubleValue * 100).rounded()))%"
    }
}
