import SwiftUI

/// Filters for the Activity list: direction, amount range and dates. Edits
/// apply live, so at the medium detent the list behind updates as you go.
struct ActivityFilterSheet: View {
    @Binding var query: TransferQuery
    @Environment(\.dismiss) private var dismiss
    @State private var minText = ""
    @State private var maxText = ""
    @FocusState private var focused: Field?

    private enum Field { case min, max }

    var body: some View {
        NavigationStack {
            Form {
                Section("Direction") {
                    Picker("Direction", selection: $query.direction) {
                        ForEach(TransferQuery.Direction.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    HStack(spacing: Theme.Spacing.m) {
                        amountField("Min", text: $minText, field: .min)
                        Text(verbatim: "–").foregroundStyle(Theme.Palette.textTertiary)
                        amountField("Max", text: $maxText, field: .max)
                    }
                    .listRowBackground(Theme.Palette.surface)
                } header: {
                    Text("Amount (USDT)")
                } footer: {
                    if let problem = amountProblem {
                        Text(problem).foregroundStyle(Theme.Palette.danger)
                    }
                }

                Section("Date") {
                    Toggle("From", isOn: dateToggle(\.from, default: defaultFrom))
                    if let from = query.from {
                        DatePicker("Start", selection: dateBinding(\.from, fallback: from),
                                   in: ...(query.to ?? .now), displayedComponents: .date)
                    }
                    Toggle("To", isOn: dateToggle(\.to, default: .now))
                    if let to = query.to {
                        DatePicker("End", selection: dateBinding(\.to, fallback: to),
                                   in: (query.from ?? .distantPast)...Date.now, displayedComponents: .date)
                    }
                }
                .listRowBackground(Theme.Palette.surface)

                if let counterparty = query.counterparty {
                    Section("Counterparty") {
                        HStack {
                            Text(counterparty.shortAddress).font(.body.monospaced())
                            Spacer()
                            Button("Remove", role: .destructive) { query.counterparty = nil }
                        }
                    }
                    .listRowBackground(Theme.Palette.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Palette.background)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset", action: reset).disabled(!hasFilters)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .animation(.snappy, value: query)
        }
        .onAppear {
            minText = query.minUnits.map(Self.editable) ?? ""
            maxText = query.maxUnits.map(Self.editable) ?? ""
        }
        .onChange(of: minText) { _, text in query.minUnits = Self.parse(text) }
        .onChange(of: maxText) { _, text in query.maxUnits = Self.parse(text) }
    }

    private func amountField(_ title: LocalizedStringKey, text: Binding<String>, field: Field) -> some View {
        TextField(title, text: text)
            .keyboardType(.decimalPad)
            .font(Theme.Typography.amount(17, weight: .medium).monospacedDigit())
            .focused($focused, equals: field)
            .padding(.vertical, Theme.Spacing.xxs)
    }

    /// Everything but the search text, which lives in the search field.
    private var hasFilters: Bool {
        var filters = query
        filters.text = ""
        return filters.isActive
    }

    private var amountProblem: LocalizedStringKey? {
        if (!minText.isEmpty && Self.parse(minText) == nil) || (!maxText.isEmpty && Self.parse(maxText) == nil) {
            return "Enter an amount like 25.50"
        }
        if let low = query.minUnits, let high = query.maxUnits, low > high {
            return "Min is above max, so nothing can match"
        }
        return nil
    }

    private var defaultFrom: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    }

    private func dateToggle(_ key: WritableKeyPath<TransferQuery, Date?>, default value: Date) -> Binding<Bool> {
        Binding(get: { query[keyPath: key] != nil },
                set: { query[keyPath: key] = $0 ? value : nil })
    }

    private func dateBinding(_ key: WritableKeyPath<TransferQuery, Date?>, fallback: Date) -> Binding<Date> {
        Binding(get: { query[keyPath: key] ?? fallback },
                set: { query[keyPath: key] = $0 })
    }

    private func reset() {
        let text = query.text
        query = TransferQuery()
        query.text = text
        minText = ""
        maxText = ""
        focused = nil
    }

    /// Decimal-pad input in any region: a comma separator reads as the point.
    static func parse(_ text: String) -> UInt64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        return USDT.units(from: trimmed.replacingOccurrences(of: ",", with: "."))
    }

    /// Base units back to what someone would type: no grouping, no trailing zeros.
    static func editable(_ units: UInt64) -> String {
        let whole = units / 1_000_000
        var fraction = String(format: "%06llu", units % 1_000_000)
        while fraction.last == "0" { fraction.removeLast() }
        return fraction.isEmpty ? "\(whole)" : "\(whole).\(fraction)"
    }
}
