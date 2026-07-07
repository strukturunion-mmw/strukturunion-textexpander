import SwiftUI

struct StatisticsView: View {
    @ObservedObject var stats = StatisticsLog.shared
    @ObservedObject var store = SnippetStore.shared
    @ObservedObject var settings = AppSettings.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Statistics")
                    .font(.largeTitle.bold())

                HStack(spacing: 16) {
                    StatCard(title: "Total Expansions", value: "\(stats.totalExpansions)", systemImage: "bolt.fill")
                    StatCard(title: "Characters Saved", value: "\(stats.totalCharactersSaved)", systemImage: "textformat")
                    StatCard(title: "Time Saved", value: timeSavedString, systemImage: "clock.fill")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Last 30 Days").font(.headline)
                    BarChart(data: stats.recentDays(30))
                        .frame(height: 160)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Most Used Snippets").font(.headline)
                    ForEach(topSnippets, id: \.id) { snippet in
                        HStack {
                            Text(snippet.displayLabel).lineLimit(1)
                            Spacer()
                            Text("\(snippet.useCount)×")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 2)
                        Divider()
                    }
                    if topSnippets.isEmpty {
                        Text("No expansions yet.").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
        }
    }

    private var topSnippets: [Snippet] {
        store.allSnippets.filter { $0.useCount > 0 }.sorted { $0.useCount > $1.useCount }.prefix(10).map { $0 }
    }

    private var timeSavedString: String {
        let seconds = stats.timeSavedSeconds(wpm: settings.typingSpeedWPM)
        if seconds < 60 { return String(format: "%.0fs", seconds) }
        if seconds < 3600 { return String(format: "%.0fm", seconds / 60) }
        return String(format: "%.1fh", seconds / 3600)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let systemImage: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage).foregroundStyle(Color.accentColor)
            Text(value).font(.title2.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct BarChart: View {
    let data: [StatisticsLog.DayStat]

    private var maxValue: Int { max(1, data.map { $0.expansions }.max() ?? 1) }

    var body: some View {
        GeometryReader { geo in
            let barWidth = max(2, geo.size.width / CGFloat(max(1, data.count)) - 3)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(data) { day in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(day.expansions > 0 ? 0.85 : 0.15))
                        .frame(width: barWidth,
                               height: max(2, geo.size.height * CGFloat(day.expansions) / CGFloat(maxValue)))
                        .help("\(day.day): \(day.expansions) expansions")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}
