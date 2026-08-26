import SwiftUI
import UIKit

struct osrsNativeCalcChrome: View {
    @ObservedObject var session: osrsNativeCalcSession
    var onHeightChange: (CGFloat) -> Void
    @Environment(\.osrsTheme) private var osrsTheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            osrsNativeCalcView(session: session)
                .fixedSize(horizontal: true, vertical: false)
        }
        .accessibilityIdentifier("native-calc-overflow")
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityValue("calculator")
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: osrsNativeCalcFormHeightKey.self,
                    value: max(geo.size.height, 160)
                )
            }
        )
        .onPreferenceChange(osrsNativeCalcFormHeightKey.self, perform: onHeightChange)
    }
}

struct osrsNativeCalcFormHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 420
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct osrsNativeCalcView: View {
    @ObservedObject var session: osrsNativeCalcSession
    @Environment(\.osrsTheme) var osrsTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(bannerError ?? "")
                .foregroundStyle(osrsTheme.error)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(bannerError == nil ? 0 : 1)
                .accessibilityHidden(bannerError == nil)
                .accessibilityIdentifier("native-calc-error")
                .accessibilityValue(bannerError ?? "")

            ForEach(session.visibleInputs(), id: \.name) { input in
                control(for: input)
            }

            Button("Submit") {
                session.submitNow()
            }
            .tint(osrsTheme.primary)
            .accessibilityIdentifier("native-calc-submit")

            if !session.statusMessage.isEmpty {
                Text(session.statusMessage)
                    .font(.footnote)
                    .foregroundStyle(osrsTheme.secondaryTextColor)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(osrsTheme.background.opacity(0.97))
        .foregroundStyle(osrsTheme.primaryTextColor)
        .tint(osrsTheme.primary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("native-calc-form")
    }

    private var bannerError: String? {
        if let error = session.hiscoresError, !error.isEmpty { return error }
        if let error = session.formError, !error.isEmpty { return error }
        return nil
    }

    @ViewBuilder
    private func control(for input: osrsNativeCalcInput) -> some View {
        switch input.type {
        case .hs, .rsn, .string:
            VStack(alignment: .leading, spacing: 8) {
                Text(input.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(osrsTheme.primaryTextColor)
                HStack {
                    osrsNativeCalcDraftField(
                        name: input.name,
                        label: input.label,
                        text: session.values[input.name] ?? input.defaultValue,
                        onChange: { session.setValue(input.name, $0, submit: false) }
                    )
                    if input.type == .hs {
                        Button("Lookup") {
                            session.lookupHiscores()
                        }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("native-calc-lookup")
                    }
                }
            }
        case .int, .number:
            VStack(alignment: .leading, spacing: 8) {
                Text(input.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(osrsTheme.primaryTextColor)
                stepper(input)
            }
        case .select:
            VStack(alignment: .leading, spacing: 8) {
                Text(input.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(osrsTheme.primaryTextColor)
                    .accessibilityLabel(input.label)
                    .accessibilityIdentifier("native-calc-label-\(input.name)")
                picker(input)
                    .labelsHidden()
                    .pickerStyle(.menu)
            }
        case .buttonSelect:
            VStack(alignment: .leading, spacing: 8) {
                Text(input.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(osrsTheme.primaryTextColor)
                chips(input)
            }
        case .toggleSwitch, .toggleButton, .check:
            Toggle(isOn: boolBinding(input.name)) {
                Text(input.label)
                    .foregroundStyle(osrsTheme.primaryTextColor)
            }
            .tint(osrsTheme.accent)
            .accessibilityIdentifier("native-calc-field-\(input.name)")
        default:
            EmptyView()
        }
    }

    private func stepper(_ input: osrsNativeCalcInput) -> some View {
        HStack(spacing: 8) {
            Button {
                session.step(input.name, delta: -1)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Decrease \(input.label)")

            osrsNativeCalcDraftField(
                name: input.name,
                label: input.label,
                text: session.values[input.name] ?? input.defaultValue,
                keyboard: .numberPad,
                centered: true,
                onChange: { session.setValue(input.name, $0, submit: false) },
                onCommit: { session.setValue(input.name, $0, submit: true) }
            )

            Button {
                session.step(input.name, delta: 1)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Increase \(input.label)")
        }
    }

    private func picker(_ input: osrsNativeCalcInput) -> some View {
        Picker(input.label, selection: pickerBinding(input)) {
            ForEach(input.options, id: \.self) { option in
                Text(option)
                    .foregroundStyle(osrsTheme.primaryTextColor)
                    .tag(option)
            }
        }
        .tint(osrsTheme.primaryTextColor)
        .accessibilityLabel(input.label)
        .accessibilityIdentifier("native-calc-field-\(input.name)")
        .accessibilityHint("Menu")
    }

    private func chips(_ input: osrsNativeCalcInput) -> some View {
        HStack(spacing: 8) {
            ForEach(input.options, id: \.self) { option in
                let selected = (session.values[input.name] ?? input.defaultValue) == option
                Button(option) { session.setValue(input.name, option) }
                    .buttonStyle(.bordered)
                    .tint(selected ? osrsTheme.accent : osrsTheme.outline)
                    .foregroundStyle(selected ? osrsTheme.onSurface : osrsTheme.primaryTextColor)
            }
        }
        .accessibilityIdentifier("native-calc-field-\(input.name)")
    }

    private func pickerBinding(_ input: osrsNativeCalcInput) -> Binding<String> {
        Binding(
            get: { session.values[input.name] ?? input.defaultValue },
            set: { session.setValue(input.name, $0) }
        )
    }

    private func boolBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: {
                let value = (session.values[name] ?? "").lowercased()
                return value == "true" || value == "1" || value == "yes" || value == "on"
            },
            set: { session.setValue(name, $0 ? "true" : "false") }
        )
    }
}

private struct osrsNativeCalcDraftField: View {
    @Environment(\.osrsTheme) private var osrsTheme
    let name: String
    let label: String
    let text: String
    let keyboard: UIKeyboardType
    let centered: Bool
    let onChange: (String) -> Void
    let onCommit: ((String) -> Void)?
    @State private var draft: String
    @FocusState private var focused: Bool

    init(
        name: String,
        label: String,
        text: String,
        keyboard: UIKeyboardType = .default,
        centered: Bool = false,
        onChange: @escaping (String) -> Void,
        onCommit: ((String) -> Void)? = nil
    ) {
        self.name = name
        self.label = label
        self.text = text
        self.keyboard = keyboard
        self.centered = centered
        self.onChange = onChange
        self.onCommit = onCommit
        _draft = State(initialValue: text)
    }

    var body: some View {
        TextField(label, text: $draft)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .multilineTextAlignment(centered ? .center : .leading)
            .focused($focused)
            .padding(10)
            .background(osrsTheme.surfaceVariant)
            .foregroundStyle(osrsTheme.onSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("native-calc-field-\(name)")
            .onChange(of: draft) { _, value in
                onChange(value)
            }
            .onChange(of: focused) { _, isFocused in
                if isFocused {
                    osrsBlankViewFirstResponderDump.capture(reason: "native-calc-\(name)")
                } else {
                    onCommit?(draft)
                }
            }
            .onChange(of: text) { _, value in
                if !focused, draft != value {
                    draft = value
                }
            }
    }
}
