const std = @import("std");
pub fn Heap(comptime T: type) type {
    return struct {
        const Self = @This();
        const CompareFunc = *const fn (a: T, b: T) bool;
        arena: std.mem.Allocator,
        buf: []T,
        size: usize,
        items: usize,
        cmp: CompareFunc,

        pub fn init(arena: std.mem.Allocator, size: usize, cmp: CompareFunc) !Self {
            return .{
                .arena = arena,
                .size = size,
                .buf = try arena.alloc(T, size),
                .items = 0,
                .cmp = cmp,
            };
        }

        fn parent(pos: usize) usize {
            return (pos - 1) / 2;
        }
        pub fn insert(self: *Self, val: T) !void {
            self.buf[self.items] = val;
            self.items += 1;
            if (self.items == self.size) {
                self.size *= 2;
                self.buf = try self.arena.realloc(self.buf, self.size);
            }

            var idx = self.items - 1;
            while (idx > 0 and self.cmp(
                self.buf[idx],
                self.buf[parent(idx)],
            )) {
                std.mem.swap(T, &self.buf[idx], &self.buf[parent(idx)]);
                idx = parent(idx);
            }
        }

        pub fn get(self: *Self) ?T {
            if (self.items == 0) {
                return null;
            }
            const item = self.buf[0];
            self.items -= 1;
            self.buf[0] = self.buf[self.items];
            self.heapify(0);
            return item;
        }

        fn heapify(self: *Self, idx: usize) void {
            const left = 2 * idx + 1;
            const right = 2 * idx + 2;
            var child_idx = idx;

            if (left < self.items and self.cmp(self.buf[left], self.buf[child_idx])) {
                child_idx = left;
            }

            if (right < self.items and self.cmp(self.buf[right], self.buf[child_idx])) {
                child_idx = right;
            }

            if (child_idx != idx) {
                std.mem.swap(T, &self.buf[child_idx], &self.buf[idx]);
                self.heapify(child_idx);
            }
        }
    };
}

fn min(a: usize, b: usize) bool {
    return a < b;
}

fn myCmpFun(a: usize, b: usize) bool {
    return a > b;
}
