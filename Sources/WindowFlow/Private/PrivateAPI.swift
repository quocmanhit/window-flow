import ApplicationServices
import Darwin

enum PrivateAPI {
    // Layout-compatible with the Carbon ProcessSerialNumber; passed as a raw pointer because C function types cannot name Swift structs.
    struct PSN {
        var high: UInt32 = 0
        var low: UInt32 = 0
    }

    typealias AXGetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    typealias AXCreateWithRemoteToken = @convention(c) (CFData) -> Unmanaged<AXUIElement>?
    typealias SetFrontProcessWithOptions = @convention(c) (UnsafeMutableRawPointer, UInt32, UInt32) -> Int32
    typealias PostEventRecordTo = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<UInt8>) -> Int32
    typealias GetProcessForPID = @convention(c) (pid_t, UnsafeMutableRawPointer) -> Int32
    typealias MainConnectionID = @convention(c) () -> Int32
    typealias CopySpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    typealias SetSymbolicHotKeyEnabled = @convention(c) (Int32, Bool) -> Int32

    // Both images are already loaded by AppKit; dlopen keeps the lookups independent of link order.
    private static let loaded: Void = {
        _ = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY)
        _ = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    }()

    private static func resolve<T>(_ name: String, as type: T.Type) -> T? {
        _ = loaded
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    static let axGetWindow = resolve("_AXUIElementGetWindow", as: AXGetWindow.self)
    static let axCreateWithRemoteToken = resolve("_AXUIElementCreateWithRemoteToken", as: AXCreateWithRemoteToken.self)
    static let setFrontProcessWithOptions = resolve("_SLPSSetFrontProcessWithOptions", as: SetFrontProcessWithOptions.self)
    static let postEventRecordTo = resolve("SLPSPostEventRecordTo", as: PostEventRecordTo.self)
    static let getProcessForPID = resolve("GetProcessForPID", as: GetProcessForPID.self)
    // The SLS names are tried first; CGS are the older aliases of the same functions.
    static let mainConnectionID = resolve("SLSMainConnectionID", as: MainConnectionID.self)
        ?? resolve("CGSMainConnectionID", as: MainConnectionID.self)
    static let copySpacesForWindows = resolve("SLSCopySpacesForWindows", as: CopySpacesForWindows.self)
        ?? resolve("CGSCopySpacesForWindows", as: CopySpacesForWindows.self)
    // Only used by the optional Cmd-Tab fallback in SwitcherController.
    static let setSymbolicHotKeyEnabled = resolve("CGSSetSymbolicHotKeyEnabled", as: SetSymbolicHotKeyEnabled.self)
}
