import Foundation

extension Duration {
    /// Convert Swift `Duration` (seconds + attoseconds) to `TimeInterval` (Double seconds).
    var asTimeInterval: TimeInterval {
        let c = self.components
        return TimeInterval(c.seconds) + TimeInterval(c.attoseconds) / 1_000_000_000_000_000_000
    }
}
