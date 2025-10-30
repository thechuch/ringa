import Foundation

struct Meeting: Identifiable, Hashable {
    let identifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let attendeeCount: Int

    var id: String { identifier }

    var formattedTimeRange: String {
        "\(startDate.formattedTime()) – \(endDate.formattedTime())"
    }
}
