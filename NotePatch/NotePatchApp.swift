//
//  NotePatchApp.swift
//  NotePatch
//
//  Created by M5性能释放6W on 2026/07/09.
//

import SwiftUI

@main
struct NotePatchApp: App {
    @StateObject private var localization = AppLocalization.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(localization)
                .environment(\.locale, localization.locale)
        }
    }
}
