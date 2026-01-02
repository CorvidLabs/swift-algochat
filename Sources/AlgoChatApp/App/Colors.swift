import SwiftUI

#if os(macOS)
import AppKit
#endif

extension Color {
    static var chatBubbleBackground: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(.systemGray5)
        #endif
    }

    static var inputBackground: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(.systemGray6)
        #endif
    }

    static var secondaryBackground: Color {
        #if os(macOS)
        Color(NSColor.controlBackgroundColor)
        #else
        Color(.secondarySystemBackground)
        #endif
    }
}
