const std = @import("std");
const expect = std.testing.expect;

var value: usize = 0;
var num_of_bits: usize = 0;

pub const BitWriter = struct {
    const Self = @This();

    num_of_bits: u3,
    writer: std.io.AnyWriter,
    value: u8,

    pub fn init(writer: std.io.AnyWriter) !Self {
        return .{
            .num_of_bits = 0,
            .writer = writer,
            .value = 0,
        };
    }

    pub fn write(self: *Self, buf: []const u1) !usize {
        var bits_written: usize = 0;
        for (buf) |c| {
            if (c == 1) {
                self.value |= @as(u8, 1) << @as(u3, 7 - self.num_of_bits);
            }
            self.num_of_bits +%= 1;
            if (self.num_of_bits == 0) {
                try self.writer.writeByte(self.value);
                bits_written += 8;
                self.value = 0;
            }
        }
        return bits_written;
    }
    pub fn flush(self: *Self) !usize {
        if (self.num_of_bits == 0) {
            return 0;
        }
        defer {
            self.num_of_bits = 0;
            self.value = 0;
        }
        try self.writer.writeByte(self.value);
        return self.num_of_bits; // bits written
    }
};

// test "write_one_byte" {
//     var one_byte = [_]u1{ 1, 1, 1, 1, 1, 1, 1, 1 };
//     var array = std.ArrayList(u8).init(std.testing.allocator);
//     defer array.deinit();
//     var bit_writer = try BitWriter.init(array.writer().any());
//     const bytes_written = try bit_writer.write(&one_byte);

//     std.debug.print("bits_written: {}\n", .{bytes_written});
//     try std.testing.expect(bytes_written == one_byte.len);
//     try std.testing.expect(array.items.len == 1);
// }

// test "write_bytes" {
//     const total_bits = 1_048_576;
//     var buf: [total_bits]u1 = undefined;

//     for (0..total_bits) |i| {
//         buf[i] = if (@mod(i, 2) == 0) 1 else 0;
//     }

//     var array = std.ArrayList(u8).init(std.testing.allocator);
//     defer array.deinit();
//     var bit_writer = try BitWriter.init(array.writer().any());

//     var bits_written = try bit_writer.write(&buf);
//     std.debug.print("Bits Written: {}/{}\n", .{ bits_written, total_bits });
//     bits_written += try bit_writer.flush();
//     std.debug.print("Bits Written: {}/{}\n", .{ bits_written, total_bits });

//     try expect(bits_written / 8 == array.items.len);
// }

// test "write_non_full_bytes" {
//     const total_bits = 20;
//     var buf: [total_bits]u1 = undefined;

//     for (0..total_bits) |i| {
//         buf[i] = if (@mod(i, 2) == 0) 1 else 0;
//     }

//     var array = std.ArrayList(u8).init(std.testing.allocator);
//     defer array.deinit();
//     var bit_writer = try BitWriter.init(array.writer().any());

//     var bits_written = try bit_writer.write(&buf);
//     std.debug.print("Bits Written: {}/{}\n", .{ bits_written, total_bits });
//     try expect(bits_written == 16);

//     bits_written += try bit_writer.flush();
//     std.debug.print("Bits Written: {}/{}\n", .{ bits_written, total_bits });
//     try expect(bits_written == total_bits);
//     std.debug.print("{}\n", .{array.items.len});
//     try expect(array.items.len == 3);
// }
