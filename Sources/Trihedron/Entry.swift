import Foundation

struct Entry: Identifiable, Codable, Equatable {
    var id = UUID()
    var text = ""
    var visible = true
    var colorIndex = 0
}
