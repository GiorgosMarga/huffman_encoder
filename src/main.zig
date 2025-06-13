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
                try huff.encode_directory(path);
            } else {
                try huff.decode_directory(path);
            }
        },
        .file => {
            if (std.mem.eql(u8, mode, "decode")) {
                try huff.decode(path);
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
    var encoder = Huffman.init();
    defer encoder.deinit();
    try encoder.encode("encode_large_test.txt");

    var decoder = Huffman.init();
    defer decoder.deinit();
    try decoder.decode("encode_large_test.txt.my_zip");
}
