const std = @import("std");
const Heap = @import("heap.zig").Heap;
const BitWriter = @import("bitwriter.zig").BitWriter;
const BitReader = @import("bitreader.zig").BitReader;
const Hash = std.hash.Wyhash;
pub const Huffman = struct {
    const Frequencies = struct {
        freqs: []u16,
        symbols: []u8,
        idx: usize,
        allocator: std.mem.Allocator,

        fn init(allocator: std.mem.Allocator, num_of_symbols: usize) Frequencies {
            return .{
                .freqs = allocator.alloc(u16, num_of_symbols) catch |err| {
                    std.debug.panic("{s}\n", .{@errorName(err)});
                },
                .symbols = allocator.alloc(u8, num_of_symbols) catch |err| {
                    std.debug.panic("{s}\n", .{@errorName(err)});
                },
                .allocator = allocator,
                .idx = 0,
            };
        }
        fn reset(self: *Frequencies) void {
            self.idx = 0;
        }
        fn insert(self: *Frequencies, symbol: u8) void {
            for (0..self.idx) |i| {
                if (self.symbols[i] == symbol) {
                    self.freqs[i] += 1;
                    return;
                }
            }
            self.symbols[self.idx] = symbol;
            self.freqs[self.idx] = 1;
            self.idx += 1;
        }
        fn deinit(self: *Frequencies) void {
            self.allocator.free(self.freqs);
            self.allocator.free(self.symbols);
        }
        fn count(self: Frequencies) usize {
            return self.idx;
        }

        fn insert_with_freq(self: *Frequencies, symbol: u8, freq: u16) void {
            std.debug.assert(self.idx < self.symbols.len);
            self.freqs[self.idx] = freq;
            self.symbols[self.idx] = symbol;
            self.idx += 1;
        }
    };
    const Node = struct {
        freq: usize,
        left: ?*Node,
        right: ?*Node,
        symbol: u8,
        is_leaf: bool = false,
        fn cmpNodes(self: *Node, other: *Node) bool {
            if (self.freq == other.freq) {
                return self.symbol < other.symbol;
            }
            return self.freq <= other.freq;
        }
    };

    const CodeMap = std.AutoHashMap(u8, []u1);

    tree: ?*Node,
    arena: *std.heap.ArenaAllocator,
    codes: CodeMap = undefined,
    freqs: Frequencies = undefined,

    const Self = @This();

    pub fn init(arena: *std.heap.ArenaAllocator) Self {
        var self: Self = .{
            .tree = null,
            .arena = arena,
        };
        self.freqs = Frequencies.init(self.arena.allocator(), 1 << 20);
        self.codes = CodeMap.init(self.arena.allocator());
        return self;
    }

    pub fn deinit(self: *Self) void {
        var code_iter = self.codes.iterator();
        while (code_iter.next()) |code| {
            self.arena.allocator().free(code.value_ptr.*);
        }
        self.codes.deinit();
        // self.freqs.deinit();
    }
    fn generateEncodedFilePath(self: Self, file_path: []const u8) ![]u8 {
        const my_zip_extension = ".my_zip";

        var iterator = std.mem.splitSequence(u8, file_path, ".");
        const filename = iterator.next();
        if (filename) |f_name| {
            const total_length = f_name.len + my_zip_extension.len;
            var compressed_file_name = try self.arena.allocator().alloc(u8, total_length);
            for (file_path, 0..) |ch, idx| {
                compressed_file_name[idx] = ch;
            }
            for (my_zip_extension, 0..) |ch, idx| {
                compressed_file_name[idx + f_name.len] = ch;
            }
            return compressed_file_name;
        }
        return error.InvalidFileName;
    }

    fn createPath(self: *Self, paths: []const []const u8) ![]u8 {
        var total_length: usize = 0;
        for (paths) |path| {
            total_length += path.len;
        }
        // for /
        total_length += paths.len;
        const path = try self.arena.allocator().alloc(u8, total_length + 1);

        std.mem.copyForwards(u8, path[0..1], ".");

        var prev_length: usize = 1;
        for (paths) |p| {
            std.mem.copyForwards(u8, path[prev_length .. prev_length + 1], "/");
            prev_length += 1;
            std.mem.copyForwards(u8, path[prev_length .. p.len + prev_length], p);
            prev_length += p.len;
        }
        return path;
    }

    pub fn encodeDirectory(self: *Self, dir_path: []const u8) !void {
        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
        defer dir.close();

        const compressed_folder_name = try self.createPath(&[_][]u8{ dir_path, ".myzip" });
        defer self.arena.allocator().free(compressed_folder_name);

        std.debug.print("New folder name: {s}\n", .{compressed_folder_name});

        std.fs.cwd().makeDir(compressed_folder_name) catch {};

        var iter = try dir.walk(self.arena.allocator());
        defer iter.deinit();

        while (try iter.next()) |entry| {
            const encoded_path = try self.createPath(&[_][]const u8{ compressed_folder_name, entry.path });
            defer self.arena.allocator().free(encoded_path);
            const file_path = try self.createPath(&[_][]const u8{ dir_path, entry.path });
            defer self.arena.allocator().free(file_path);

            try self.encode(file_path, encoded_path);
        }
    }

    fn encodeChunk(self: *Self, content: []const u8, writer: std.io.AnyWriter) !usize {
        for (content) |c| {
            self.freqs.insert(c);
        }
        self.tree = try self.generateHuffmanTree();
        try self.generateCodes();

        var bit_writer = try BitWriter.init(writer);

        var bits_written: usize = 0;

        for (content) |c| {
            if (self.codes.get(c)) |code| {
                // std.debug.print("code: {any}\n", .{c});
                bits_written += try bit_writer.write(code);
            }
        }
        bits_written += try bit_writer.flush();

        // std.debug.print("Wrote: {} bytes ({} bits)  from {} bytes; Shrink percentage: {}%\n", .{ bits_written / 8, bits_written, content.len, (content.len - (bits_written / 8)) * 100 / content.len });
        return bits_written;
    }

    pub fn encode(self: *Self, file_path: []const u8, new_file_name: ?[]const u8) !void {
        const file = std.fs.cwd().openFile(file_path, .{ .mode = .read_only }) catch |err| {
            std.debug.print("Error opening file: {s}\n", .{@errorName(err)});
            return;
        };
        defer file.close();
        const compressed_file_name = if (new_file_name != null) new_file_name.? else try self.generateEncodedFilePath(file_path);

        const compressed_file = std.fs.cwd().createFile(compressed_file_name, .{}) catch |err| {
            std.debug.print("Error creating file: ({s}) {s}\n", .{ compressed_file_name, @errorName(err) });
            return;
        };
        defer compressed_file.close();

        var bits_written: usize = 0;
        const writer = compressed_file.writer().any();
        var total_bytes_read: usize = 0;
        var bytes_read: usize = 0;
        var total_bytes_written: usize = 0;
        const content = try self.arena.allocator().alloc(u8, 1 << 12);
        std.debug.assert(try compressed_file.getPos() == 0);
        while (true) {
            bytes_read = try file.read(content);
            if (bytes_read == 0) {
                break;
            }
            total_bytes_read += bytes_read;

            // skip the first 2 bytes
            // to write the number of bits written
            compressed_file.seekBy(2) catch |err| {
                std.debug.print("Error seeking: {s}\n", .{@errorName(err)});
            };

            bits_written = try self.encodeChunk(content[0..bytes_read], writer);
            _ = compressed_file.seekTo(total_bytes_written) catch |err| {
                std.debug.print("Error seeking to 0: {s}\n", .{@errorName(err)});
            };

            const t: u16 = @truncate(bits_written);
            writer.writeInt(u16, t, .big) catch |err| {
                std.debug.print("Error writing bits: {s}\n", .{@errorName(err)});
            };
            bits_written += @sizeOf(u16) * 8;
            compressed_file.seekFromEnd(0) catch |err| {
                bits_written += @sizeOf(u16) * 8;
                std.debug.print("Error seeking to end: {s}\n", .{@errorName(err)});
            };
            // write how many symbols exist
            // read up to 1<<12 bytes, so there cant be more than 1<<12 symbols,
            // u16 is enough
            const num_of_symbols: u16 = @truncate(self.freqs.count());

            try writer.writeInt(u16, num_of_symbols, .little);
            bits_written += @sizeOf(u16) * 8;
            // write each symbol together with its frequency
            bits_written += try self.writeHuffmanTree(writer) * 8;
            while (bits_written % 8 != 0) bits_written += 1;
            total_bytes_written += bits_written / 8;
            self.resetMaps();
            self.resetHuffmanTree(self.tree);
            self.tree = null;
        }
        std.debug.print("Wrote a total of {} bytes\n", .{total_bytes_written});
    }

    fn resetHuffmanTree(self: *Self, curr: ?*Node) void {
        if (curr) |c| {
            self.resetHuffmanTree(c.left);
            self.resetHuffmanTree(c.right);
            self.arena.allocator().destroy(c);
        }
    }
    fn resetMaps(self: *Self) void {
        var iter = self.codes.valueIterator();
        while (iter.next()) |v| {
            self.arena.allocator().free(v.*);
        }

        self.codes.clearRetainingCapacity();
        self.freqs.reset();
    }

    fn writeHuffmanTree(self: *Self, writer: std.io.AnyWriter) !usize {
        var bytes_written: usize = 0;
        const symbols = self.freqs.count();

        const symbols_buf = try self.arena.allocator().alloc(u8, symbols);
        const freq_buf = try self.arena.allocator().alloc(u16, symbols);

        std.mem.copyForwards(u8, symbols_buf, self.freqs.symbols[0..symbols]);
        std.mem.copyForwards(u16, freq_buf, self.freqs.freqs[0..symbols]);

        bytes_written = try writer.write(symbols_buf);
        for (freq_buf) |freq| {
            try writer.writeInt(u16, freq, .little);
            bytes_written += @sizeOf(u16);
        }

        return bytes_written;
    }

    pub fn decodeDirectory(self: *Self, dir_path: []const u8) !void {
        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
        defer dir.close();

        var splitted_dir_name = std.mem.splitAny(u8, dir_path, ".");
        const folder_name = splitted_dir_name.peek();
        if (folder_name == null) {
            return error.InvalidFolderName;
        }

        try std.fs.cwd().makeDir(folder_name.?);

        var iter = try dir.walk(self.arena.allocator());
        defer iter.deinit();
        while (try iter.next()) |entry| {
            const decoded_file_path = try self.createPath(&[_][]const u8{ folder_name.?, entry.path });
            const file_path = try self.createPath(&[_][]const u8{ dir_path, entry.path });
            defer self.arena.allocator().free(decoded_file_path);
            defer self.arena.allocator().free(file_path);
            try self.decode(file_path, decoded_file_path);
        }
    }
    pub fn decode(self: *Self, encoded_file_path: []const u8, decoded_file_path: []const u8) !void {
        const decoded_file = std.fs.cwd().createFile(decoded_file_path, .{}) catch |err| {
            std.debug.print("Error creating decoded file ({s}): {s}\n", .{ decoded_file_path, @errorName(err) });
            return;
        };
        defer decoded_file.close();

        const encoded_file = std.fs.cwd().openFile(encoded_file_path, .{ .mode = .read_only }) catch |err| {
            std.debug.print("Error opening encoded file ({s}): {s}\n", .{ encoded_file_path, @errorName(err) });
            return;
        };
        const reader = encoded_file.reader().any();
        defer encoded_file.close();

        var bits_to_read: u16 = undefined;
        var bit_reader = try BitReader.init(reader);
        var bits_read: usize = 0;
        const bits_buf = try self.arena.allocator().alloc(u1, 1 << 20);
        var total_bytes_read: usize = 0;
        while (true) {
            bits_to_read = reader.readInt(u16, .big) catch |err| {
                switch (err) {
                    error.EndOfStream => break,
                    else => std.debug.print("Error: {s}\n", .{@errorName(err)}),
                }
                break;
            };
            if (bits_to_read == 0) break;

            bits_read = try bit_reader.readBitsBuf(bits_buf[0..bits_to_read]);
            std.debug.assert(bits_read == bits_to_read);
            while (bits_read % 8 != 0) bits_read += 1;
            // bit reader reads by chunks of 1024 bytes
            // need to fix file pos
            // bytes_read + 2 (2 is the size of the header that contains the total number of bits of this chunk)
            const new_position: u64 = @intCast(bits_read / 8);
            try encoded_file.seekTo(total_bytes_read + new_position + 2);

            const tree_size = try reader.readInt(u16, .little);
            bits_read += @sizeOf(u16) * 8;

            try self.decodeHuffmanTree(reader, tree_size);
            bits_read += (@sizeOf(u8) + @sizeOf(u16)) * 8 * tree_size;

            self.tree = try self.generateHuffmanTree();

            try self.generateCodes();

            var code: [1024]u1 = undefined;
            var code_idx: usize = 0;
            for (0..bits_to_read) |idx| {
                code[code_idx] = bits_buf[idx];
                code_idx += 1;
                const val = self.getSymbol(code[0..code_idx]);
                if (val) |v| {
                    try decoded_file.writer().writeByte(v);
                    code_idx = 0;
                }
            }

            self.resetHuffmanTree(self.tree);
            self.resetMaps();
            self.tree = null;
            std.debug.assert(bits_read % 8 == 0);
            // +2 because of the initial u16 read to get the bits of the encoded chunk
            total_bytes_read += bits_read / 8 + 2;
        }

        std.debug.print("Read a total of {} bytes\n", .{total_bytes_read});
    }
    fn getSymbol(self: Self, code: []const u1) ?u8 {
        if (self.tree.?.is_leaf) {
            // edge case if only one symbol exists
            return self.tree.?.symbol;
        }
        var curr = self.tree;
        var code_idx: usize = 0;
        while (curr) |c| {
            if (code[code_idx] == 1) {
                curr = c.right;
            } else {
                curr = c.left;
            }
            code_idx += 1;
            if (code_idx >= code.len) {
                break;
            }
        }
        if (curr) |c| {
            if (c.is_leaf) {
                return c.symbol;
            }
        }
        return null;
    }

    fn decodeHuffmanTree(self: *Self, reader: std.io.AnyReader, num_of_symbols: u16) !void {
        const symbols_buf = try self.arena.allocator().alloc(u8, num_of_symbols);
        const read_symbols = try reader.read(symbols_buf);
        std.debug.assert(read_symbols == num_of_symbols);
        for (symbols_buf) |symbol| {
            const freq = try reader.readInt(u16, .little);
            self.freqs.insert_with_freq(symbol, freq);
        }
    }
    fn generateHuffmanTree(
        self: *Self,
    ) !*Node {
        const num_of_symbols = self.freqs.count();
        var heap = try Heap(*Node).init(self.arena.allocator(), num_of_symbols, Node.cmpNodes);

        var node: *Node = undefined;

        for (0..num_of_symbols) |idx| {
            node = try self.arena.allocator().create(Node);
            node.* = .{
                .freq = self.freqs.freqs[idx],
                .symbol = self.freqs.symbols[idx],
                .left = null,
                .right = null,
                .is_leaf = true,
            };
            try heap.insert(node);
        }

        while (heap.items > 1) {
            const node1 = heap.get();
            const node2 = heap.get();

            node = try self.arena.allocator().create(Node);

            node.* = .{ .left = node1, .right = node2, .symbol = '+', .is_leaf = false, .freq = node1.?.freq + node2.?.freq };
            try heap.insert(node);
        }
        std.debug.assert(heap.items == 1);
        const root = heap.get();
        if (root) |r| {
            return r;
        }
        return error.InvalidTree;
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
        var path: [256]u1 = undefined;
        try self.iterateTree(self.tree, &path, 0);
    }

    fn iterateTree(self: *Self, curr: ?*Node, path: []u1, depth: usize) !void {
        if (self.tree.?.is_leaf) {
            // edge case only one symbol
            const code = try self.arena.allocator().alloc(u1, 1);
            code[0] = 0;
            try self.codes.put(curr.?.symbol, code);
            return;
        }
        if (curr) |c| {
            if (c.is_leaf) {
                const code = try self.arena.allocator().dupe(u1, path[0..depth]);
                try self.codes.put(c.symbol, code);
                return;
            }

            path[depth] = 0;
            try self.iterateTree(c.left, path, depth + 1);

            path[depth] = 1;
            try self.iterateTree(c.right, path, depth + 1);
        }
    }
};
