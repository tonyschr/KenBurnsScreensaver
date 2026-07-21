//
//  AppDelegate.swift
//  KenBurnsScreensaver
//
//  Created by Tony Schreiner on 7/21/26.
//

import Foundation
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
