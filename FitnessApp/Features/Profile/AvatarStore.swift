//
//  AvatarStore.swift
//  页面 17：本地头像文件的读写。
//
//  头像图片压缩后保存在 App 自己的 Application Support 目录（与 JSON 数据同根），
//  不进入系统相册、不上传云端。文件名存进 `UserProfile.avatarFileName`，
//  图片本身在这里按文件名读写。
//

import Foundation

enum AvatarStore {

    /// 头像文件所在子目录（相对 FitnessData 根目录）。
    static let subdirectory = "avatars"

    /// 头像目录 URL。与仓储的 JSON 落在同一个 Application Support 根下。
    static func directoryURL(fileManager: FileManager = .default) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return root
            .appendingPathComponent("FitnessData", isDirectory: true)
            .appendingPathComponent(subdirectory, isDirectory: true)
    }

    /// 把压缩后的头像数据写入本地，返回文件名。
    static func save(_ data: Data, fileManager: FileManager = .default) throws -> String {
        let dir = directoryURL(fileManager: fileManager)
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let name = "avatar-\(UUID().uuidString).jpg"
        try data.write(to: dir.appendingPathComponent(name), options: .atomic)
        return name
    }

    /// 头像文件 URL。文件不存在时返回 nil。
    static func url(for fileName: String, fileManager: FileManager = .default) -> URL? {
        let url = directoryURL(fileManager: fileManager).appendingPathComponent(fileName)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// 读取头像数据。文件不存在或读取失败返回 nil。
    static func data(for fileName: String, fileManager: FileManager = .default) -> Data? {
        guard let url = url(for: fileName, fileManager: fileManager) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// 删除头像文件。文件不存在时静默成功。
    static func delete(fileName: String, fileManager: FileManager = .default) throws {
        let url = directoryURL(fileManager: fileManager).appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
