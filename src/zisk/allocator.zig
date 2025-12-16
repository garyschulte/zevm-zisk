const std = @import("std");

// Linker-provided symbol for heap start
extern const _kernel_heap_bottom: u8;

/// Implementation of sys_alloc_aligned for Zisk zkVM
/// This is a simple bump allocator that allocates from the kernel heap
export fn sys_alloc_aligned(bytes: usize, alignment: usize) [*]u8 {
    // Static variable to track current heap position
    const State = struct {
        var heap_pos: usize = 0;
    };

    // Initialize heap position on first call
    if (State.heap_pos == 0) {
        State.heap_pos = @intFromPtr(&_kernel_heap_bottom);
    }

    // Align the current position
    const offset = State.heap_pos & (alignment - 1);
    if (offset != 0) {
        State.heap_pos += alignment - offset;
    }

    // Allocate the memory
    const ptr: [*]u8 = @ptrFromInt(State.heap_pos);
    State.heap_pos += bytes;

    return ptr;
}

/// Zisk-based allocator that uses sys_alloc_aligned
/// This is a pure bump allocator (no free/realloc support)
pub const ZiskAllocator = struct {
    const Self = @This();

    /// Initialize the Zisk allocator (no-op, uses global heap)
    pub fn init() Self {
        return Self{};
    }

    /// Allocate memory with specified size and alignment
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = ret_addr;
        const alignment = @as(usize, 1) << @intFromEnum(ptr_align);

        // Call our sys_alloc_aligned implementation
        const ptr = sys_alloc_aligned(len, alignment);
        return ptr;
    }

    /// Resize an allocation (not supported, returns false)
    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false;
    }

    /// Free memory (no-op, bump allocator doesn't support free)
    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
        // No-op: Zisk allocator is a bump allocator
    }

    /// Remap an allocation (not supported, returns null)
    fn remap(ctx: *anyopaque, old_buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = old_buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return null;
    }

    /// Get the Zig allocator interface
    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = remap,
            },
        };
    }
};

/// Simple bump allocator for bare-metal environments
/// This allocator provides a basic memory allocation strategy where memory
/// is allocated sequentially from a fixed buffer without any deallocation support.
pub const BumpAllocator = struct {
    buffer: []u8,
    offset: usize,

    const Self = @This();

    /// Initialize a bump allocator with a fixed buffer
    pub fn init(buffer: []u8) Self {
        return Self{
            .buffer = buffer,
            .offset = 0,
        };
    }

    /// Reset the allocator, freeing all allocations
    pub fn reset(self: *Self) void {
        self.offset = 0;
    }

    /// Get the current usage statistics
    pub fn getStats(self: *const Self) struct { used: usize, total: usize, free: usize } {
        return .{
            .used = self.offset,
            .total = self.buffer.len,
            .free = self.buffer.len - self.offset,
        };
    }

    /// Align an offset to the specified alignment
    fn alignOffset(offset: usize, alignment: usize) usize {
        const mask = alignment - 1;
        return (offset + mask) & ~mask;
    }

    /// Allocate memory with specified size and alignment
    fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
        _ = ret_addr;
        const self: *Self = @ptrCast(@alignCast(ctx));
        const alignment = @as(usize, 1) << @intFromEnum(ptr_align);

        const aligned_offset = alignOffset(self.offset, alignment);
        const new_offset = aligned_offset + len;

        if (new_offset > self.buffer.len) {
            // Out of memory
            return null;
        }

        const result = self.buffer[aligned_offset..new_offset];
        self.offset = new_offset;
        return result.ptr;
    }

    /// Resize an allocation (not supported in bump allocator, returns false)
    fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return false;
    }

    /// Free memory (no-op for bump allocator)
    fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
        _ = ctx;
        _ = buf;
        _ = buf_align;
        _ = ret_addr;
        // No-op: bump allocator doesn't support individual frees
    }

    /// Remap an allocation (not supported in bump allocator, returns null)
    fn remap(ctx: *anyopaque, old_buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = old_buf;
        _ = buf_align;
        _ = new_len;
        _ = ret_addr;
        return null;
    }

    /// Get the Zig allocator interface
    pub fn allocator(self: *Self) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
                .remap = remap,
            },
        };
    }
};

/// Arena allocator that can reset all allocations at once
/// This is similar to BumpAllocator but with better ergonomics for reset patterns
pub const ArenaAllocator = struct {
    bump: BumpAllocator,

    const Self = @This();

    pub fn init(buffer: []u8) Self {
        return Self{
            .bump = BumpAllocator.init(buffer),
        };
    }

    pub fn reset(self: *Self) void {
        self.bump.reset();
    }

    pub fn allocator(self: *Self) std.mem.Allocator {
        return self.bump.allocator();
    }

    pub fn getStats(self: *const Self) struct { used: usize, total: usize, free: usize } {
        return self.bump.getStats();
    }
};

/// Fixed buffer allocator wrapper for convenient usage
pub fn FixedBufferAllocator(comptime size: usize) type {
    return struct {
        buffer: [size]u8,
        bump: BumpAllocator,

        const Self = @This();

        pub fn init() Self {
            var self = Self{
                .buffer = undefined,
                .bump = undefined,
            };
            self.bump = BumpAllocator.init(&self.buffer);
            return self;
        }

        pub fn reset(self: *Self) void {
            self.bump.reset();
        }

        pub fn allocator(self: *Self) std.mem.Allocator {
            return self.bump.allocator();
        }

        pub fn getStats(self: *const Self) struct { used: usize, total: usize, free: usize } {
            return self.bump.getStats();
        }
    };
}

// Tests
test "BumpAllocator basic allocation" {
    var buffer: [1024]u8 = undefined;
    var bump = BumpAllocator.init(&buffer);
    const alloc = bump.allocator();

    const slice1 = try alloc.alloc(u8, 100);
    try std.testing.expectEqual(@as(usize, 100), slice1.len);

    const slice2 = try alloc.alloc(u8, 200);
    try std.testing.expectEqual(@as(usize, 200), slice2.len);

    const stats = bump.getStats();
    try std.testing.expect(stats.used >= 300);
    try std.testing.expectEqual(@as(usize, 1024), stats.total);
}

test "BumpAllocator alignment" {
    var buffer: [1024]u8 = undefined;
    var bump = BumpAllocator.init(&buffer);
    const alloc = bump.allocator();

    const slice1 = try alloc.alloc(u8, 1);
    _ = slice1;

    const slice2 = try alloc.alloc(u64, 1);
    const addr = @intFromPtr(slice2.ptr);
    try std.testing.expectEqual(@as(usize, 0), addr % 8);
}

test "BumpAllocator out of memory" {
    var buffer: [100]u8 = undefined;
    var bump = BumpAllocator.init(&buffer);
    const alloc = bump.allocator();

    const result = alloc.alloc(u8, 200);
    try std.testing.expectError(error.OutOfMemory, result);
}

test "BumpAllocator reset" {
    var buffer: [1024]u8 = undefined;
    var bump = BumpAllocator.init(&buffer);
    const alloc = bump.allocator();

    _ = try alloc.alloc(u8, 500);
    var stats = bump.getStats();
    try std.testing.expect(stats.used >= 500);

    bump.reset();
    stats = bump.getStats();
    try std.testing.expectEqual(@as(usize, 0), stats.used);
}
