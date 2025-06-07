const std = @import("std");
pub fn readFileBuf(buf: []u8, file_path: []const u8) !usize {
    const file = try std.fs.cwd().openFile(file_path, .{ .mode = .read_only });
    defer file.close();

    return file.read(buf);
}

pub fn readFile(allocator: std.mem.Allocator, file_path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(file_path, .{ .mode = .read_only });

    var bytes_read: usize = 0;
    var buf_size: usize = 1024;
    var total_bytes_read: usize = 0;
    var buf = try allocator.alloc(u8, buf_size);

    while (true) {
        bytes_read = try file.read(buf[total_bytes_read..]);
        if (bytes_read == 0) {
            return allocator.realloc(buf, total_bytes_read);
        }
        total_bytes_read += bytes_read;
        if (total_bytes_read >= buf_size) {
            buf_size *= 2;
            buf = try allocator.realloc(buf, buf_size);
        }
    }
    return buf;
}

test "read_file_buf" {
    var buf: [1024]u8 = .{0} ** 1024;
    const file_path = "test_encode.txt";

    const bytes_read = try readFileBuf(&buf, file_path);
    try std.testing.expect(bytes_read == 1024);
    std.debug.print("{s}", .{buf});
}

test "read_file_allocator" {
    const allocator = std.testing.allocator;

    const buf = try readFile(allocator, "test_encode.txt");

    defer allocator.free(buf);

    std.debug.print("{s}", .{buf});
}
