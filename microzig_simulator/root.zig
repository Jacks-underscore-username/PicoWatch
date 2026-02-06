const std = @import("std");

const Pin = struct {};

const Gpio = struct {
    Pin: @TypeOf(Pin),
};

const StateMachine = struct {};

const Pio = struct {
    Pio: @TypeOf(Pio),
    StateMachine: @TypeOf(StateMachine),
};

const Hal = struct {
    pio: Pio,
    gpio: Gpio,
};

pub const hal: Hal = .{
    .pio = .{
        .Pio = Pio,
        .StateMachine = StateMachine,
    },
    .gpio = .{
        .Pin = Pin,
    },
};
