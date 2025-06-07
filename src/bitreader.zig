const std = @import("std");
const BitWriter = @import("bitwriter.zig").BitWriter;

pub const BitReader = struct {
    reader: std.io.AnyReader,
    const Self = @This();
    pub fn init(reader: std.io.AnyReader) !Self {
        return .{
            .reader = reader,
        };
    }
    pub fn readBitsBuf(self: Self, buf: []u1) !usize {
        var bits_read: usize = 0;
        var file_buf: [1024]u8 = undefined;
        var bytes_read: usize = 0;
        while (bits_read < buf.len) {
            bytes_read = try self.reader.read(&file_buf);
            if (bytes_read == 0) {
                break;
            }
            bytes_loop: for (0..bytes_read) |num_idx| {
                var byte = file_buf[num_idx];
                for (0..8) |_| {
                    buf[bits_read] = if (byte & 0b10000000 != 0) 1 else 0;
                    byte <<= 1;
                    bits_read += 1;
                    if (bits_read >= buf.len) {
                        break :bytes_loop;
                    }
                }
            }
        }
        return bits_read;
    }
};

// test "reader" {
//     var bit_writer = try BitWriter.init("test_reader.txt");
//     defer bit_writer.deinit();

//     var bit_reader = try BitReader.init("test_reader.txt");
//     defer bit_reader.deinit();

//     const write_buf: [8]u1 = .{ 0, 1, 0, 1, 0, 1, 0, 1 };
//     var read_buf: [8]u1 = undefined;

//     const bits_written = try bit_writer.write(&write_buf);

//     const bits_read = try bit_reader.readBitsBuf(&read_buf);

//     try std.testing.expect(bits_written == bits_read);

//     for (0..bits_written) |i| {
//         try std.testing.expect(write_buf[i] == read_buf[i]);
//     }
// }

// test "read_with_smaller_buffer" {
//     var bit_writer = try BitWriter.init("test_reader.txt");
//     defer bit_writer.deinit();
//     const write_buf = [_]u1{ 1, 1, 1, 1 };
//     _ = try bit_writer.write(&write_buf);

//     var bit_reader = try BitReader.init("test_reader.txt");
//     defer bit_reader.deinit();

//     var read_buf: [18]u1 = undefined;

//     const bits_read = try bit_reader.readBitsBuf(&read_buf);

//     std.debug.print("Bits read: {}\n", .{bits_read});

//     try std.testing.expect(bits_read == 8);
// }
