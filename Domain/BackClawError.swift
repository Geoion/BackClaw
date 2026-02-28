import Foundation

enum BackClawError: LocalizedError {
    case invalidSourcePath
    case sourcePathNotReachable(String)
    case cannotCreateArchive(String)
    case backupFailed(String)
    case previewFileNotText
    case previewFileTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidSourcePath:
            return "源目录无效。"
        case .sourcePathNotReachable(let path):
            return "源目录不可访问：\(path)"
        case .cannotCreateArchive(let reason):
            return "无法创建备份存档：\(reason)"
        case .backupFailed(let reason):
            return "备份失败：\(reason)"
        case .previewFileNotText:
            return "该文件不是可预览的文本文件。"
        case .previewFileTooLarge:
            return "文件过大，暂不支持预览。"
        }
    }
}
