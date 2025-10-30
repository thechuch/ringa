# Meeting Alert

Meeting Alert is a lightweight macOS SwiftUI application that monitors your calendars and sends you a notification before each upcoming meeting.

## Features

- Requests access to the calendars available on your Mac and filters upcoming events that look like meetings.
- Displays meetings scheduled in the next 24 hours with details such as time range, location, and attendee count.
- Allows you to enable alerts and choose how many minutes before a meeting the reminder should appear.
- Automatically refreshes the meeting list every five minutes and reschedules notifications when your preferences change.

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15 or later

## Getting Started

1. Open `MeetingAlert.xcodeproj` in Xcode.
2. Select the **MeetingAlert** scheme and choose **My Mac** as the run destination.
3. Build and run the project.
4. When prompted, grant the app access to your calendars and notifications.

Once permissions are granted, the app will list your upcoming meetings and schedule reminders using the lead time you selected.
