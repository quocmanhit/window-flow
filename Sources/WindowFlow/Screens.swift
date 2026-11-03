import AppKit
import WindowFlowCore

enum Screens {
    static func visibleFrames() -> [(full: CGRect, visible: CGRect)] {
        // The first screen is the primary one, whose height anchors the CG coordinate flip.
        guard let primary = NSScreen.screens.first else { return [] }
        let height = primary.frame.height
        return NSScreen.screens.map {
            (flipped($0.frame, primaryHeight: height), flipped($0.visibleFrame, primaryHeight: height))
        }
    }
}
