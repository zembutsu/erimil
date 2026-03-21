//
//  ErimilApp.swift
//  Erimil
//
//  Created by Masahito Zembutsu on 2025/12/13.
//

import SwiftUI

@main
struct ErimilApp: App {
    init() {
        // #216: Start background loading immediately on launch.
        // CacheManager.shared is lazy — without this, loading wouldn't start
        // until first access (e.g., when user clicks a source).
        _ = CacheManager.shared
    }
    
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
