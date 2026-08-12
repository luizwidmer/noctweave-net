import Darwin
import Foundation

public enum NoctwebSecureFileIOError: Error {
    case notFound
    case inaccessible
    case notRegular
    case tooLarge
    case changedDuringRead
    case unsafeDirectory
}

/// Bounded, no-follow local persistence shared by Lab and Browser.
///
/// The final path component is opened once and validated through its file
/// descriptor. Private writes replace the destination from a mode-0600
/// temporary file inside a verified mode-0700 directory.
public enum NoctwebSecureFileIO {
    public static func read(
        from url: URL,
        maximumBytes: Int,
        allowEmpty: Bool = false,
        requirePrivateOwner: Bool = false
    ) throws -> Data {
        guard maximumBytes >= 0, maximumBytes < Int.max else {
            throw NoctwebSecureFileIOError.tooLarge
        }
        let directory: Int32 = url.deletingLastPathComponent()
            .withUnsafeFileSystemRepresentation { path in
                guard let path else { return -1 }
                return Darwin.open(
                    path,
                    O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
                )
            }
        guard directory >= 0 else {
            throw NoctwebSecureFileIOError.inaccessible
        }
        defer { _ = Darwin.close(directory) }
        let name = url.lastPathComponent
        guard isSafeFilename(name) else {
            throw NoctwebSecureFileIOError.inaccessible
        }
        let descriptor: Int32 = name.withCString { filename in
            Darwin.openat(
                directory,
                filename,
                O_RDONLY | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK
            )
        }
        guard descriptor >= 0 else {
            throw errno == ENOENT
                ? NoctwebSecureFileIOError.notFound
                : .inaccessible
        }
        defer { _ = Darwin.close(descriptor) }

        let before = try validate(
            descriptor,
            maximumBytes: maximumBytes,
            allowEmpty: allowEmpty,
            requirePrivateOwner: requirePrivateOwner
        )
        var data = Data()
        data.reserveCapacity(min(Int(before.st_size), maximumBytes))
        var buffer = [UInt8](
            repeating: 0,
            count: max(1, min(64 * 1_024, maximumBytes + 1))
        )
        while true {
            let remaining = maximumBytes + 1 - data.count
            guard remaining > 0 else {
                throw NoctwebSecureFileIOError.tooLarge
            }
            let requested = min(buffer.count, remaining)
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return Darwin.read(descriptor, base, requested)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else {
                throw NoctwebSecureFileIOError.inaccessible
            }
            if count == 0 { break }
            data.append(contentsOf: buffer[0..<count])
            guard data.count <= maximumBytes else {
                throw NoctwebSecureFileIOError.tooLarge
            }
        }

        var after = stat()
        guard Darwin.fstat(descriptor, &after) == 0,
              sameFileAndVersion(before, after),
              data.count == Int(after.st_size),
              allowEmpty || !data.isEmpty else {
            throw NoctwebSecureFileIOError.changedDuringRead
        }
        return data
    }

    public static func writePrivate(
        _ data: Data,
        to fileURL: URL,
        maximumBytes: Int,
        allowEmpty: Bool = false
    ) throws {
        guard maximumBytes >= 0,
              maximumBytes < Int.max,
              data.count <= maximumBytes,
              allowEmpty || !data.isEmpty else {
            throw NoctwebSecureFileIOError.tooLarge
        }
        let directoryURL = fileURL.deletingLastPathComponent()
        try ensurePrivateDirectory(at: directoryURL)
        let directory: Int32 = directoryURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return Darwin.open(
                path,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard directory >= 0 else {
            throw NoctwebSecureFileIOError.unsafeDirectory
        }
        defer { _ = Darwin.close(directory) }

        let name = fileURL.lastPathComponent
        guard isSafeFilename(name) else {
            throw NoctwebSecureFileIOError.inaccessible
        }
        let temporaryName = ".\(name).\(UUID().uuidString.lowercased()).tmp"
        let descriptor: Int32 = temporaryName.withCString { temporary in
            Darwin.openat(
                directory,
                temporary,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                mode_t(0o600)
            )
        }
        guard descriptor >= 0 else {
            throw NoctwebSecureFileIOError.inaccessible
        }
        var descriptorIsOpen = true
        var temporaryExists = true
        defer {
            if descriptorIsOpen { _ = Darwin.close(descriptor) }
            if temporaryExists {
                temporaryName.withCString {
                    _ = Darwin.unlinkat(directory, $0, 0)
                }
            }
        }

        guard Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else {
            throw NoctwebSecureFileIOError.inaccessible
        }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var written = 0
            while written < raw.count {
                let count = Darwin.write(
                    descriptor,
                    base.advanced(by: written),
                    raw.count - written
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else {
                    throw NoctwebSecureFileIOError.inaccessible
                }
                written += count
            }
        }
        guard Darwin.fsync(descriptor) == 0 else {
            throw NoctwebSecureFileIOError.inaccessible
        }
        guard Darwin.close(descriptor) == 0 else {
            descriptorIsOpen = false
            throw NoctwebSecureFileIOError.inaccessible
        }
        descriptorIsOpen = false

        let renameResult = temporaryName.withCString { temporary in
            name.withCString { destination in
                Darwin.renameat(directory, temporary, directory, destination)
            }
        }
        guard renameResult == 0, Darwin.fsync(directory) == 0 else {
            throw NoctwebSecureFileIOError.inaccessible
        }
        temporaryExists = false
    }

    private static func ensurePrivateDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let descriptor: Int32 = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return -1 }
            return Darwin.open(
                path,
                O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
            )
        }
        guard descriptor >= 0 else {
            throw NoctwebSecureFileIOError.unsafeDirectory
        }
        defer { _ = Darwin.close(descriptor) }
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              status.st_uid == geteuid(),
              (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR),
              Darwin.fchmod(descriptor, mode_t(0o700)) == 0 else {
            throw NoctwebSecureFileIOError.unsafeDirectory
        }
    }

    private static func isSafeFilename(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/")
    }

    private static func validate(
        _ descriptor: Int32,
        maximumBytes: Int,
        allowEmpty: Bool,
        requirePrivateOwner: Bool
    ) throws -> stat {
        var status = stat()
        guard Darwin.fstat(descriptor, &status) == 0,
              (status.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              status.st_size >= 0 else {
            throw NoctwebSecureFileIOError.notRegular
        }
        guard UInt64(status.st_size) <= UInt64(maximumBytes) else {
            throw NoctwebSecureFileIOError.tooLarge
        }
        guard allowEmpty || status.st_size > 0 else {
            throw NoctwebSecureFileIOError.notRegular
        }
        if requirePrivateOwner {
            guard status.st_uid == geteuid(),
                  (status.st_mode & mode_t(0o077)) == 0 else {
                throw NoctwebSecureFileIOError.notRegular
            }
        }
        return status
    }

    private static func sameFileAndVersion(_ lhs: stat, _ rhs: stat) -> Bool {
        lhs.st_dev == rhs.st_dev
            && lhs.st_ino == rhs.st_ino
            && lhs.st_size == rhs.st_size
            && lhs.st_mtimespec.tv_sec == rhs.st_mtimespec.tv_sec
            && lhs.st_mtimespec.tv_nsec == rhs.st_mtimespec.tv_nsec
            && lhs.st_ctimespec.tv_sec == rhs.st_ctimespec.tv_sec
            && lhs.st_ctimespec.tv_nsec == rhs.st_ctimespec.tv_nsec
    }
}
