import Foundation

extension String.StringInterpolation {
  mutating func appendInterpolation(macaddr: [UInt8], separator: String = ":") {
    let string = macaddr.map { elem in
      String(format: "%02x", elem)
    }.joined(separator: separator)

    appendLiteral(string)
  }
}
