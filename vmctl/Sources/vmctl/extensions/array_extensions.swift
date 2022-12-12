import Foundation

extension Array {
  func chunked(by distance: Int) -> [[Element]] {
    let indicesSequence = stride(from: startIndex, to: endIndex, by: distance)
    let array: [[Element]] = indicesSequence.map {
      let newIndex = $0.advanced(by: distance) > endIndex ? endIndex : $0.advanced(by: distance)

      return Array(self[$0 ..< newIndex])
    }

    return array
  }
}
