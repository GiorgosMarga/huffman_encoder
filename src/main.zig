const std = @import("std");
const Huffman = @import("huffman.zig").Huffman;
pub fn main() !void {
    std.debug.print("Hello from huffman encoding\n", .{});
}

test "huffman" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const allocator = arena.allocator();
    defer arena.deinit();

    var encoder = Huffman.init(allocator);
    try encoder.encode("encode_small_test.txt");

    var decoder = Huffman.init(allocator);
    try decoder.decode("encode_small_test.txt.my_zip");
}
