import SwiftUI

@main
struct MeetingAlertApp: App {
    @StateObject private var store = MeetingStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
        .commands {
            CommandMenu("Meetings") {
                Button("Refresh Meetings") {
                    store.refreshMeetings()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Request Calendar Access") {
                    store.requestCalendarAccess()
                }
            }
        }
    }
}
