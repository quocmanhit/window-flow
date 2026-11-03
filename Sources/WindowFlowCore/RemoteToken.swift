public enum RemoteToken {
    /// 20-byte token for `_AXUIElementCreateWithRemoteToken`: pid, 4 zero bytes, 0x636f636f, element id (all little endian).
    public static func bytes(pid: Int32, elementID: UInt64) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(20)
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { out.append(contentsOf: $0) }
        }
        append(pid)
        append(UInt32(0))
        append(UInt32(0x636f636f))
        append(elementID)
        return out
    }
}
