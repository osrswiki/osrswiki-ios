import SwiftUI
import WebKit

struct osrsNativeCalcView: View {
    @ObservedObject var session: osrsNativeCalcSession
    @Environment(\.osrsTheme) var osrsTheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Agility calculator")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(osrsTheme.primaryTextColor)
                    .accessibilityIdentifier("native-calc-agility-title")

                if !session.introCopy.isEmpty {
                    Text(session.introCopy)
                        .font(.body)
                        .foregroundStyle(osrsTheme.secondaryTextColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("native-calc-agility-copy")
                }

                ForEach(session.visibleInputs(), id: \.name) { input in
                    control(for: input)
                }

                if let error = session.hiscoresError, !error.isEmpty {
                    Text(error)
                        .foregroundStyle(osrsTheme.error)
                        .font(.footnote)
                }

                Button("Submit") {
                    session.submitNow()
                }
                .buttonStyle(.borderedProminent)
                .tint(osrsTheme.primary)
                .foregroundStyle(osrsTheme.onPrimary)
                .accessibilityIdentifier("native-calc-submit")

                if !session.statusMessage.isEmpty {
                    Text(session.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(osrsTheme.secondaryTextColor)
                }

                if !session.resultHTML.isEmpty {
                    osrsNativeCalcResultWebView(html: session.resultDocument)
                        .frame(minHeight: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("native-calc-result")
                }
            }
            .padding(16)
            .padding(.top, 56)
            .padding(.bottom, 96)
        }
        .background(osrsTheme.background)
        .accessibilityIdentifier("native-calc-agility")
    }

    @ViewBuilder
    private func control(for input: osrsNativeCalcInput) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(input.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(osrsTheme.primaryTextColor)
            switch input.type {
            case .hs, .rsn, .string:
                HStack {
                    TextField(input.label, text: binding(input.name))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(osrsTheme.surfaceVariant)
                        .foregroundStyle(osrsTheme.onSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    if input.type == .hs {
                        Button("Lookup") { session.lookupHiscores() }
                            .buttonStyle(.bordered)
                    }
                }
            case .int, .number:
                stepper(input)
            case .select:
                picker(input)
            case .buttonSelect:
                chips(input)
            case .toggleSwitch, .toggleButton, .check:
                Toggle(isOn: boolBinding(input.name)) {
                    Text(input.label)
                        .foregroundStyle(osrsTheme.primaryTextColor)
                }
                .labelsHidden()
                .tint(osrsTheme.accent)
            default:
                EmptyView()
            }
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

            TextField(input.label, text: binding(input.name))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .padding(10)
                .background(osrsTheme.surfaceVariant)
                .foregroundStyle(osrsTheme.onSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("native-calc-field-\(input.name)")

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
        Menu {
            ForEach(input.options, id: \.self) { option in
                Button(option) { session.setValue(input.name, option) }
            }
        } label: {
            HStack {
                Text(session.values[input.name] ?? input.defaultValue)
                    .foregroundStyle(osrsTheme.onSurface)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .foregroundStyle(osrsTheme.secondaryTextColor)
            }
            .padding(12)
            .background(osrsTheme.surfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityIdentifier("native-calc-field-\(input.name)")
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

    private func binding(_ name: String) -> Binding<String> {
        Binding(
            get: { session.values[name] ?? "" },
            set: { session.setValue(name, $0) }
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

private struct osrsNativeCalcResultWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.accessibilityIdentifier = "native-calc-result-web"
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.loadHTMLString(html, baseURL: URL(string: osrsWikiWebViewUrl.wikiOrigin))
    }
}
