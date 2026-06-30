import Foundation

enum OutputStrategy: String, CaseIterable, Codable {
    case sameDirectory
    case customDirectory
    case customDirectoryPreserveStructure

    var displayName: String {
        switch self {
        case .sameDirectory: return "原目录输出"
        case .customDirectory: return "自定义目录"
        case .customDirectoryPreserveStructure: return "自定义+保留结构"
        }
    }
}
