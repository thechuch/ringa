import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: MeetingStore
    @State private var showingSettingsHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { store.notificationsEnabled },
                    set: { store.setNotificationsEnabled($0) }
                )) {
                    Text("Enable meeting alerts")
                }
                .disabled(!store.canEnableNotifications)

                if store.notificationsEnabled {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Notify me")
                            Slider(value: Binding(
                                get: { store.notificationLeadTimeMinutes },
                                set: { store.updateLeadTime(to: $0) }
                            ), in: 1...30, step: 1)
                            Text("\(Int(store.notificationLeadTimeMinutes)) minutes before")
                                .frame(width: 180, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                        Text("Alerts are scheduled for upcoming meetings in the next 24 hours.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            if let error = store.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundColor(.orange)
            }

            Text("Upcoming Meetings")
                .font(.headline)

            Group {
                if store.upcomingMeetings.isEmpty {
                    emptyState
                } else {
                    meetingList
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Button(action: store.refreshMeetings) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: [.command])

                Spacer()

                Button("Help") {
                    showingSettingsHelp = true
                }
            }
        }
        .padding(24)
        .frame(minWidth: 540, minHeight: 480)
        .sheet(isPresented: $showingSettingsHelp) {
            SettingsHelpView(isPresented: $showingSettingsHelp)
        }
        .onAppear {
            store.bootstrap()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meeting Alert")
                .font(.largeTitle).bold()

            HStack(spacing: 8) {
                Image(systemName: store.authorizationIconName)
                    .foregroundColor(store.authorizationTint)
                Text(store.authorizationMessage)
                    .font(.callout)
            }
        }
    }

    private var meetingList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(store.upcomingMeetings) { meeting in
                    MeetingRow(meeting: meeting)
                        .transition(.opacity)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No meetings scheduled in the next 24 hours.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(meeting.formattedTimeRange)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if let location = meeting.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            if meeting.attendeeCount > 0 {
                Label("\(meeting.attendeeCount) attendee\(meeting.attendeeCount == 1 ? "" : "s")", systemImage: "person.2")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(NSColor.windowBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
    }
}

struct SettingsHelpView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Allow Calendar and Notification Access")
                .font(.title2).bold()

            Text("Meeting Alert needs permission to read your calendars and deliver notifications. You can update these permissions in System Settings > Privacy & Security.")

            VStack(alignment: .leading, spacing: 8) {
                Text("Troubleshooting")
                    .font(.headline)
                Text("• Ensure the calendars containing your meetings are checked in the app's calendar list.\n• If notifications are missing, verify that alerts are allowed for Meeting Alert under Notifications settings.")
            }

            HStack {
                Spacer()
                Button("Done") {
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(minWidth: 420)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(MeetingStore.preview)
    }
}
