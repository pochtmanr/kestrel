import Foundation

/// Keccak-256 as used by Ethereum and TRON (original Keccak padding 0x01,
/// not the NIST SHA3-256 padding 0x06). Needed to derive TRON addresses.
enum Keccak256 {
    private static let roundConstants: [UInt64] = [
        0x0000_0000_0000_0001, 0x0000_0000_0000_8082, 0x8000_0000_0000_808A, 0x8000_0000_8000_8000,
        0x0000_0000_0000_808B, 0x0000_0000_8000_0001, 0x8000_0000_8000_8081, 0x8000_0000_0000_8009,
        0x0000_0000_0000_008A, 0x0000_0000_0000_0088, 0x0000_0000_8000_8009, 0x0000_0000_8000_000A,
        0x0000_0000_8000_808B, 0x8000_0000_0000_008B, 0x8000_0000_0000_8089, 0x8000_0000_0000_8003,
        0x8000_0000_0000_8002, 0x8000_0000_0000_0080, 0x0000_0000_0000_800A, 0x8000_0000_8000_000A,
        0x8000_0000_8000_8081, 0x8000_0000_0000_8080, 0x0000_0000_8000_0001, 0x8000_0000_8000_8008,
    ]
    private static let rotations: [UInt64] = [1, 3, 6, 10, 15, 21, 28, 36, 45, 55, 2, 14, 27, 41, 56, 8, 25, 43, 62, 18, 39, 61, 20, 44]
    private static let piLanes: [Int] = [10, 7, 11, 17, 18, 3, 5, 16, 8, 21, 24, 4, 15, 23, 19, 13, 12, 2, 20, 14, 22, 9, 6, 1]
    private static let rate = 136 // bytes, for a 256-bit output

    static func hash(_ input: [UInt8]) -> [UInt8] {
        var state = [UInt64](repeating: 0, count: 25)

        var message = input
        message.append(0x01)
        while message.count % rate != 0 { message.append(0) }
        message[message.count - 1] |= 0x80

        for blockStart in stride(from: 0, to: message.count, by: rate) {
            for lane in 0 ..< rate / 8 {
                var value: UInt64 = 0
                for byte in 0 ..< 8 {
                    value |= UInt64(message[blockStart + lane * 8 + byte]) << (8 * UInt64(byte))
                }
                state[lane] ^= value
            }
            permute(&state)
        }

        var output = [UInt8]()
        output.reserveCapacity(32)
        for lane in 0 ..< 4 {
            for byte in 0 ..< 8 { output.append(UInt8(truncatingIfNeeded: state[lane] >> (8 * UInt64(byte)))) }
        }
        return output
    }

    private static func rotl(_ x: UInt64, _ n: UInt64) -> UInt64 { (x << n) | (x >> (64 - n)) }

    private static func permute(_ st: inout [UInt64]) {
        var bc = [UInt64](repeating: 0, count: 5)
        for round in 0 ..< 24 {
            // θ
            for i in 0 ..< 5 { bc[i] = st[i] ^ st[i + 5] ^ st[i + 10] ^ st[i + 15] ^ st[i + 20] }
            for i in 0 ..< 5 {
                let t = bc[(i + 4) % 5] ^ rotl(bc[(i + 1) % 5], 1)
                for j in stride(from: 0, to: 25, by: 5) { st[j + i] ^= t }
            }
            // ρ and π
            var t = st[1]
            for i in 0 ..< 24 {
                let j = piLanes[i]
                let saved = st[j]
                st[j] = rotl(t, rotations[i])
                t = saved
            }
            // χ
            for j in stride(from: 0, to: 25, by: 5) {
                for i in 0 ..< 5 { bc[i] = st[j + i] }
                for i in 0 ..< 5 { st[j + i] ^= (~bc[(i + 1) % 5]) & bc[(i + 2) % 5] }
            }
            // ι
            st[0] ^= roundConstants[round]
        }
    }
}
