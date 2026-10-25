import Foundation

/// One reading of a window's percent used, kept to whole seconds and whole
/// percents so a week of history stays small.
struct UsageSample: Equatable, Sendable {
    let date: Date
    let percent: UInt8
}

/// Five bytes a sample: little-endian `UInt32` seconds since 1970, then the
/// `UInt8` percent.
enum UsageSampleCoding {
    private static let recordSize = 5

    static func encode(_ samples: [UsageSample]) -> Data {
        var data = Data()
        data.reserveCapacity(samples.count * recordSize)

        for sample in samples {
            let seconds = UInt32(clamping: Int(sample.date.timeIntervalSince1970))
            withUnsafeBytes(of: seconds.littleEndian) { data.append(contentsOf: $0) }
            data.append(sample.percent)
        }

        return data
    }

    /// A trailing partial record is ignored.
    static func decode(_ data: Data) -> [UsageSample] {
        let bytes = [UInt8](data)

        return stride(from: 0, to: bytes.count - recordSize + 1, by: recordSize).map { start in
            let seconds = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[start + $1]) << (8 * UInt32($1)) }

            return UsageSample(date: Date(timeIntervalSince1970: TimeInterval(seconds)), percent: bytes[start + 4])
        }
    }
}
