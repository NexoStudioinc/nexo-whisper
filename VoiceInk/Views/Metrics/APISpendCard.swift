import SwiftUI

/// Card del Dashboard que muestra el gasto estimado en APIs de IA.
///
/// Lee los registros desde `TokenUsageStore` (UserDefaults JSON). Si no
/// hay registros, no se renderiza (la sección queda oculta para usuarios
/// que no usan providers facturables).
struct APISpendCard: View {
    @ObservedObject private var store = TokenUsageStore.shared
    @State private var showResetConfirm = false
    private var allRecords: [TokenUsageRecord] { store.records }

    private var monthStart: Date? {
        Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: Date())
        )
    }

    private var monthRecords: [TokenUsageRecord] {
        guard let monthStart else { return [] }
        return allRecords.filter { $0.date >= monthStart }
    }

    private var monthTotal: Double { monthRecords.reduce(0) { $0 + $1.costUSD } }
    private var grandTotal: Double { allRecords.reduce(0) { $0 + $1.costUSD } }
    private var monthRequestsCount: Int { monthRecords.count }

    /// Breakdown del mes por provider: [provider: costoUSD].
    private var perProviderMonth: [(provider: String, cost: Double)] {
        let grouped = Dictionary(grouping: monthRecords, by: { $0.provider })
        return grouped
            .map { (provider: $0.key, cost: $0.value.reduce(0) { $0 + $1.costUSD }) }
            .sorted { $0.cost > $1.cost }
    }

    /// Breakdown del mes por modelo (con su provider para identificar).
    /// Top 5 modelos más caros para no inflar la card.
    private struct ModelBreakdown: Identifiable {
        let id: String  // "provider/model"
        let provider: String
        let model: String
        let cost: Double
        let requests: Int
    }
    private var perModelMonth: [ModelBreakdown] {
        let grouped = Dictionary(grouping: monthRecords, by: { "\($0.provider)/\($0.model)" })
        return grouped
            .map { key, recs -> ModelBreakdown in
                let first = recs.first!
                return ModelBreakdown(
                    id: key,
                    provider: first.provider,
                    model: first.model,
                    cost: recs.reduce(0) { $0 + $1.costUSD },
                    requests: recs.count
                )
            }
            .sorted { $0.cost > $1.cost }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        if allRecords.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.green)
                    Text("API spend (estimated)")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text("\(monthRequestsCount) requests this month")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Menu {
                        Button(role: .destructive) {
                            showResetConfirm = true
                        } label: {
                            Label("Reset usage tracking", systemImage: "arrow.counterclockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

                HStack(spacing: 24) {
                    spendCell(
                        label: Text("This month"),
                        value: monthTotal
                    )
                    Divider()
                        .frame(height: 36)
                    spendCell(
                        label: Text("All time"),
                        value: grandTotal
                    )
                }

                // Breakdown del mes por modelo (top 5 más caros).
                // Más informativo que solo por provider — muestra exactamente
                // qué modelo está consumiendo cuánto.
                if !perModelMonth.isEmpty {
                    Divider().padding(.vertical, 2)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("By model (this month)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(perModelMonth) { row in
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.model)
                                        .font(.system(size: 12, weight: .medium))
                                        .lineLimit(1)
                                    Text("\(row.provider.capitalized) · \(row.requests) req")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 6)
                                Text(formatUSD(row.cost))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Text("Estimated cost based on the input/output length of each request. Real billing depends on each provider's tokenizer.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.thinMaterial)
            )
            .confirmationDialog(
                "Reset usage tracking?",
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Reset", role: .destructive) {
                    store.reset()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes all recorded API requests. Useful for matching your tracking to a fresh billing period.")
            }
        }
    }

    private func spendCell(label: Text, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatUSD(value))
                .font(.system(size: 20, weight: .black, design: .rounded))
        }
    }

    private func formatUSD(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = amount < 0.01 ? 4 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}
