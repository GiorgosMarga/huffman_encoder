const std = @import("std");
const Huffman = @import("huffman.zig").Huffman;
pub fn main() !void {
    // var gpa = std.heap.ArenaAllocator.init(.{}){};
    // const allocator = gpa.allocator();

    // defer gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var args_iter = std.process.args();
    defer args_iter.deinit();
    _ = args_iter.skip();
    const mode = args_iter.next().?;
    const path = args_iter.next().?;
    std.debug.print("Path: {s}\n", .{path});
    const stat = std.fs.cwd().statFile(path) catch |err| {
        std.debug.print("Err: {s}\n", .{@errorName(err)});
        return;
    };

    var huff = Huffman.init(&arena);
    defer huff.deinit();
    switch (stat.kind) {
        .directory => {
            if (std.mem.eql(u8, mode, "encode")) {
                try huff.encodeDirectory(path);
            } else {
                try huff.decodeDirectory(path);
            }
        },
        .file => {
            if (std.mem.eql(u8, mode, "decode")) {
                try huff.decode(path, path);
            } else {
                try huff.encode(path, null);
            }
        },
        else => {
            std.debug.print("Need to provide a file or a folder to encode: ({s}-{})\n", .{ path, stat.kind });
        },
    }
}

test "huffman" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var encoder = Huffman.init(&arena);
    defer encoder.deinit();

    const filename_to_encode = "./test_folder/file_93943.txt";
    const encoded_file_name = ".encoded";
    const decoded_file_name = ".decoded";

    try encoder.encode(filename_to_encode, encoded_file_name);

    var decoder = Huffman.init(&arena);
    defer decoder.deinit();

    try decoder.decode(encoded_file_name, decoded_file_name);

    const original_file = try std.fs.cwd().openFile(filename_to_encode, .{});
    defer original_file.close();

    const original_data = try original_file.readToEndAlloc(arena.allocator(), 100_000);

    const decoded_file = try std.fs.cwd().openFile(decoded_file_name, .{});
    defer decoded_file.close();

    const decoded_data = try decoded_file.readToEndAlloc(arena.allocator(), 100_000);
    try std.testing.expect(cmp(decoded_data, original_data));

    try std.fs.cwd().deleteFile(decoded_file_name);
    try std.fs.cwd().deleteFile(encoded_file_name);
}

fn cmp(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) {
        std.debug.print("Wrong len {}-{}\n", .{ a.len, b.len });
        return false;
    }
    var is_ok: bool = true;

    for (0..a.len) |idx| {
        if (a[idx] != b[idx]) {
            std.debug.print("Position ({}): expected: {c} got {c}\n", .{ idx, a[idx], b[idx] });
            is_ok = false;
        }
    }
    return is_ok;
}
