import Foundation

@inline(__always)
func JPDebugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    #if DEBUG
    let s = items.map { String(describing: $0) }.joined(separator: separator)
    Swift.print(s, terminator: terminator)
    #endif
}
