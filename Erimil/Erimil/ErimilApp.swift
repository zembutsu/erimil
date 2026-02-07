//
//  ErimilApp.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//

import SwiftUI

@main
struct ErimilApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    CacheManager.shared.flushPendingWrites()
                }
        }
        
        // Settings window (⌘,)
        Settings {
            SettingsView()
        }
    }
}
