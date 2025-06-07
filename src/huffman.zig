const std = @import("std");
const Heap = @import("heap.zig").Heap;
const BitWriter = @import("bitwriter.zig").BitWriter;
const BitReader = @import("bitreader.zig").BitReader;
const Hash = std.hash.Wyhash;
pub const Huffman = struct {
    const Node = struct {
        freq: usize,
        left: ?*Node,
        right: ?*Node,
        symbol: u8,
        is_leaf: bool = false,
        fn cmpNodes(self: *Node, other: *Node) bool {
            return self.freq < other.freq;
        }
    };

    const HashMap = std.AutoHashMap(u8, []u1);
    const FreqMap = std.AutoHashMap(u8, usize);

    tree: ?*Node,
    arena: std.mem.Allocator,
    codes: HashMap,
    frequency_map: FreqMap, // replace this
    ordered_symbols: []u8,

    const Self = @This();

    fn strcpy(dst: []u8, src: []const u8) !usize {
        var bytes_copied: usize = 0;

        if (dst.len -% src.len < 0) {
            return error.InvalidSizeDst;
        }
        for (0..src.len) |i| {
            dst[i] = src[i];
            bytes_copied += 1;
        }
        return bytes_copied;
    }

    fn readFile(self: Self, file: std.fs.File) ![]u8 {
        var size: usize = 1024;
        var buf = try self.arena.alloc(u8, size);

        var total_bytes_read: usize = 0;
        var bytes_read: usize = 1;
        while (bytes_read != 0) {
            bytes_read = try file.read(buf[total_bytes_read..]);
            total_bytes_read += bytes_read;
            if (total_bytes_read == size) {
                size *= 2;
                buf = try self.arena.realloc(buf, size);
            }
        }
        return buf[0..total_bytes_read];
    }

    pub fn init(arena: std.mem.Allocator) Self {
        return .{
            .tree = null,
            .arena = arena,
            .codes = HashMap.init(arena),
            .frequency_map = FreqMap.init(arena),
            .ordered_symbols = undefined,
        };
    }
    pub fn encode(self: *Self, file_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(file_path, .{ .mode = .read_only });
        var compressed_file_name = try self.arena.alloc(u8, file_path.len + 7);

        const b = try strcpy(compressed_file_name, file_path);
        _ = try strcpy(compressed_file_name[b..], ".my_zip");
        const compressed_file = try std.fs.cwd().createFile(compressed_file_name, .{});
        const content = try self.readFile(file);
        const writer = compressed_file.writer();
        defer {
            file.close();
            compressed_file.close();
        }
        self.tree = try self.generateHuffmanTree(content);
        try self.generateCodes();

        _ = compressed_file.seekBy(2) catch |err| {
            std.debug.print("Error seeking: {s}\n", .{@errorName(err)});
        };

        var bit_writer = try BitWriter.init(writer.any());

        var bits_written: usize = 0;

        for (content) |c| {
            if (self.codes.get(c)) |code| {
                bits_written += try bit_writer.write(code);
            }
        }

        std.debug.print("Before flushing wrote: {} bits\n", .{bits_written});
        bits_written += try bit_writer.flush();
        std.debug.print("After flushing wrote: {} bits\n", .{bits_written});

        std.debug.print("Wrote: {} bytes ({})  from {} bytes; {}%\n", .{ bits_written / 8, bits_written, content.len, (content.len - (bits_written / 8)) * 100 / content.len });

        _ = compressed_file.seekTo(0) catch |err| {
            std.debug.print("Error seeking to 0: {s}\n", .{@errorName(err)});
        };

        const t: u16 = @truncate(bits_written);
        writer.writeInt(u16, t, .big) catch |err| {
            std.debug.print("Error writing bits: {s}\n", .{@errorName(err)});
        };

        compressed_file.seekFromEnd(0) catch |err| {
            std.debug.print("Error seeking to end: {s}\n", .{@errorName(err)});
        };

        std.debug.print("Writing huffman tree: {}\n", .{try compressed_file.getPos()});
        try writer.writeInt(usize, self.ordered_symbols.len, .little);
        std.debug.print("Tree size: {}\n", .{self.ordered_symbols.len}); // didnt write '+'

        try self.write_huffman_tree(writer.any());
    }

    fn write_huffman_tree(self: Self, writer: std.io.AnyWriter) !void {
        for (self.ordered_symbols) |n| {
            try writer.writeByte(n);
        }
    }
    pub fn decode(self: *Self, encoded_file_path: []const u8) !void {
        const encoded_file = try std.fs.cwd().openFile(encoded_file_path, .{ .mode = .read_only });
        const reader = encoded_file.reader();
        defer encoded_file.close();
        const total_bits: u16 = try reader.readInt(u16, .big);
        std.debug.print("A total of {} bits are written\n", .{total_bits});

        var bit_reader = try BitReader.init(reader.any());

        const bits_buf = try self.arena.alloc(u1, total_bits);
        const bits_read = try bit_reader.readBitsBuf(bits_buf);
        std.debug.print("Read a total of {} bits\n", .{bits_read});

        // const new_position: i64 = @intCast();
        try encoded_file.seekTo(107);
        std.debug.print("New position: {}\n", .{try encoded_file.getPos()});

        const tree_length = try encoded_file.reader().readInt(usize, .little);
        std.debug.print("Tree size: {}\n", .{tree_length});

        const post_order = try self.arena.alloc(u8, tree_length);

        try decode_huffman_tree(encoded_file.reader().any(), post_order);

        var node: *Node = undefined;
        var heap = try Heap(*Node).init(self.arena, 1024, Node.cmpNodes);
        for (post_order, 0..) |symbol, idx| {
            node = try self.arena.create(Node);
            if (symbol == '+') {
                continue;
            }
            node.* = .{
                .freq = idx,
                .symbol = symbol,
                .left = null,
                .right = null,
                .is_leaf = true,
            };
            try heap.insert(node);
        }
        var tree_root: *Node = undefined;
        while (heap.items > 1) {
            const node1 = try heap.get();
            const node2 = try heap.get();

            std.debug.print("Node1: {c} -> {d}\n", .{ node1.symbol, node2.freq });
            std.debug.print("Node2: {c} -> {d}\n", .{ node2.symbol, node2.freq });

            node = try self.arena.create(Node);
            node.* = .{ .left = node1, .right = node2, .symbol = '+', .is_leaf = false, .freq = node1.freq + node2.freq };
            try heap.insert(node);
            if (heap.items == 1) {
                tree_root = node;
            }
        }
        self.tree = tree_root;

        print_postorder(self.tree);
        std.debug.print("\n", .{});

        var code: [1024]u1 = undefined;
        var code_idx: usize = 0;
        for (0..bits_buf.len) |idx| {
            code[code_idx] = bits_buf[idx];
            code_idx += 1;
            const val = self.getSymbol(code[0..code_idx]);
            if (val) |v| {
                std.debug.print("{c}", .{v});
                code_idx = 0;
            }
        }
    }

    fn print_postorder(node: ?*Node) void {
        if (node) |n| {
            print_postorder(n.left);
            print_postorder(n.right);
            std.debug.print("{c} ", .{n.symbol});
        }
    }

    fn print_inorder(node: ?*Node) void {
        if (node) |n| {
            print_inorder(n.left);
            std.debug.print("{c} ", .{n.symbol});
            print_inorder(n.right);
        }
    }
    fn getSymbol(self: Self, code: []const u1) ?u8 {
        var curr = self.tree;
        var code_idx: usize = 0;
        while (curr) |c| {
            if (code[code_idx] == 1) {
                curr = c.right;
            } else {
                curr = c.left;
            }
            // if (c.symbol != '+') {
            code_idx += 1;
            // }
            if (code_idx >= code.len) {
                break;
            }
        }
        if (curr) |c| {
            std.debug.print("{c}", .{c.symbol});
            if (c.symbol != '+') {
                return c.symbol;
            }
        }
        return null;
    }

    fn find_symbol(buf: []u8, symbol: u8) usize {
        var last_idx: usize = std.math.maxInt(usize);
        for (buf, 0..) |s, idx| {
            if (s == symbol) {
                last_idx = idx;
            }
        }
        return last_idx; // Returns maxInt(usize) if not found
    }

    fn decode_huffman_tree(reader: std.io.AnyReader, postorder: []u8) !void {
        _ = try reader.read(postorder);
    }

    fn generateHuffmanTree(self: *Self, content: []u8) !*Node {
        for (content) |c| {
            const res = try self.frequency_map.getOrPut(c);
            if (res.found_existing) {
                res.value_ptr.* += 1;
            } else {
                res.value_ptr.* = 1;
            }
        }

        var node: *Node = undefined;
        var heap = try Heap(*Node).init(self.arena, 1024, Node.cmpNodes);
        var it = self.frequency_map.iterator();
        var heap_items: usize = 0;
        self.ordered_symbols = try self.arena.alloc(u8, 1024);

        while (it.next()) |entry| {
            node = try self.arena.create(Node);
            node.* = .{
                .freq = entry.value_ptr.*,
                .symbol = entry.key_ptr.*,
                .left = null,
                .right = null,
                .is_leaf = true,
            };
            try heap.insert(node);
        }
        var tree_root: *Node = undefined;
        while (heap.items > 1) {
            const node1 = try heap.get();
            const node2 = try heap.get();

            self.ordered_symbols[heap_items] = node1.symbol;
            self.ordered_symbols[heap_items + 1] = node2.symbol;
            heap_items += 2;
            std.debug.print("Node1: {c} -> {d}\n", .{ node1.symbol, node2.freq });
            std.debug.print("Node2: {c} -> {d}\n", .{ node2.symbol, node2.freq });

            node = try self.arena.create(Node);
            node.* = .{ .left = node1, .right = node2, .symbol = '+', .is_leaf = false, .freq = node1.freq + node2.freq };
            try heap.insert(node);
            if (heap.items == 1) {
                tree_root = node;
            }
        }

        self.ordered_symbols = try self.arena.realloc(self.ordered_symbols, heap_items);

        return tree_root;
    }

    fn printCode(code: []const u1) void {
        var buf: [1024]u8 = .{0} ** 1024;
        var idx: usize = 0;
        for (0..code.len) |_| {
            buf[idx] = if (code[idx] == 1) '1' else '0';
            idx += 1;
        }

        std.debug.print("{s}\n", .{buf[0..idx]});
    }
    fn generateCodes(self: *Self) !void {
        const code = try self.arena.alloc(u1, 0);
        try self.iterate_tree(self.tree, code);

        var it = self.codes.iterator();
        while (it.next()) |entry| {
            const freq = self.frequency_map.get(entry.key_ptr.*);
            std.debug.print("{c}({}): ", .{ entry.key_ptr.*, freq.? });
            printCode(entry.value_ptr.*);
        }
    }

    fn iterate_tree(self: *Self, curr: ?*Node, path: []u1) !void {
        if (curr) |c| {
            if (c.is_leaf) {
                try self.codes.put(c.symbol, path);
            }
            var left_path = try self.arena.dupe(u1, path);
            left_path = try self.arena.realloc(left_path, left_path.len + 1);
            left_path[left_path.len - 1] = 0;

            var right_path = try self.arena.dupe(u1, path);
            right_path = try self.arena.realloc(right_path, right_path.len + 1);
            right_path[right_path.len - 1] = 1;

            try self.iterate_tree(c.left, left_path);
            try self.iterate_tree(c.right, right_path);
        }
    }
};

// test "cast_to_u8" {
//     const buf = [_]u1{ 1, 1, 0, 1, 1, 0, 0, 0, 1 };

//     // std.debug.print("Value: {}\n", .{try Huffman.castToU8(&buf)});
//     try std.testing.expectError(error.InvalidCodeSize, Huffman.castToU8(&buf));
// }

test "min_heap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const items = 12;
    var heap = try Heap(*Huffman.Node).init(allocator, items, &Huffman.Node.cmpNodes);

    for (0..items) |i| {
        const node = try allocator.create(Huffman.Node);
        node.* = Huffman.Node{
            .freq = i,
            .left = null,
            .right = null,
            .symbol = ' ',
        };
        try heap.insert(node);
    }
    try std.testing.expect(heap.items == items);
    var node: *Huffman.Node = undefined;
    for (0..items) |i| {
        node = try heap.get();
        try std.testing.expect(node.freq == i);
    }

    try std.testing.expect(heap.items == 0);
}
