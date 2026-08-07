const std = @import("std");
const sys = @import("esp_idf").sys;

const MutexHandle = sys.QueueHandle_t;

pub const MutexError = error{
    FailedToCreate,
    LockFaield,
};

const Mutex = @This();

handle: MutexHandle,

pub fn init() MutexError!Mutex {
    const handle = sys.xSemaphoreCreateMutex();
    if (handle == null) {
        return MutexError.FailedToCreate;
    }
    return .{ .handle = handle };
}

pub fn deinit(self: *Mutex) void {
    sys.vSemaphoreDelete(self.handle);
}

pub fn lock(self: *Mutex) MutexError!void {
    if (sys.xSemaphoreTake(self.handle, sys.portMAX_DELAY) != sys.pdTRUE) {
        return MutexError.LockFaield;
    }
}

pub fn lockUncancelable(self: *Mutex) void {
    while (!self.tryLock(1000)) {}
}

pub fn tryLock(self: *Mutex, wait_ms: u32) bool {
    return sys.pdTRUE ==
        sys.xSemaphoreTake(
            self.handle,
            sys.pdMS_TO_TICKS(wait_ms),
        );
}

pub fn unlock(self: *Mutex) void {
    _ = sys.xSemaphoreGive(self.handle);
}
