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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if logType == .api {
                HStack(spacing: 8) {
                    Text(log.responseCode)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Spacer()
                    Text(responseTimeText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
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
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
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
        ApiLogRowView(log: .previewSamples[0], logType: .api)
        ApiLogRowView(log: .previewSamples[1], logType: .api)
        ApiLogRowView(log: .previewSamples[2], logType: .api)
    }
    .padding()
}
#endif
