//
//  ApiLogRowView.swift
//  Core
//
//  Created by Henry David Lie on 10/06/26.
//

import SwiftUI

struct ApiLogRowView: View {
    let log: ApiLog
    let logType: LogEventType

    private var endpoint: String {
        log.url.components(separatedBy: "/").last ?? log.url
    }

    private var responseTimeText: String {
        String(format: "%.2f s", Double(log.responseTime) ?? 0)
    }

    private var dateText: String {
        log.date.apiLogFormatted()
    }

    private var isPending: Bool { log.state == .pending }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // EventTracker rows have no status or timing, but a restored one
            // still needs its marker — so the badge row also appears for those.
            if logType.isHTTP || log.isRestored {
                HStack(spacing: 6) {
                    if logType.isHTTP {
                        if isPending {
                            pendingBadge
                        } else {
                            Text(log.responseCode)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(statusColor)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }

                    if log.isRestored {
                        restoredBadge
                    }

                    Spacer()

                    if logType.isHTTP {
                        // An in-flight request has no duration yet — showing
                        // "0.00 s" would read as an impossibly fast response.
                        Text(isPending ? "—" : responseTimeText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Text(endpoint)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            Text(log.url)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(2)

            Text(dateText)
                .font(.system(size: 11))
                .foregroundColor(Color(.tertiaryLabel))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isPending ? Color.accentColor.opacity(0.5) : Color(.systemGray4),
                        lineWidth: 1)
        )
        // Dim the whole row while in flight, so completed entries are what the
        // eye lands on when scanning.
        .opacity(isPending ? 0.55 : 1)
    }

    /// Marks an entry that came from disk rather than this session. Sized to sit
    /// flush beside the status badge.
    private var restoredBadge: some View {
        Image(systemName: "archivebox")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color(.tertiarySystemFill))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityLabel("From a previous session")
    }

    /// Stands in for the status badge until a real code arrives.
    private var pendingBadge: some View {
        HStack(spacing: 5) {
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 10, height: 10)
            Text("Pending")
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color.gray)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var statusColor: Color {
        switch Int(log.responseCode) ?? 0 {
        case 200..<300: return .green
        case 300..<400: return .orange
        case 400...:    return .red
        default:        return .gray
        }
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 12) {
        ApiLogRowView(log: .previewPendingSample, logType: .api)
        ApiLogRowView(log: .previewSamples[1], logType: .api)
        ApiLogRowView(log: .previewSamples[2], logType: .api)
        ApiLogRowView(log: .previewSamples[3], logType: .api)
    }
    .padding()
}
#endif
