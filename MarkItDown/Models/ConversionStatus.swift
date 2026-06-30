import SwiftUI

enum ConversionStatus: Equatable {
    case pending
    case converting
    case completed
    case failed

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .converting: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .secondary
        case .converting: return .accentColor
        case .completed: return .green
        case .failed: return .red
        }
    }

    var label: String {
        switch self {
        case .pending: return "待转换"
        case .converting: return "转换中"
        case .completed: return "已完成"
        case .failed: return "失败"
        }
    }
}
