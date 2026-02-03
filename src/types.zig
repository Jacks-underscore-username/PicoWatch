const std = @import("std");

pub fn expectFunc(comptime func: anytype) void {
    if (!std.mem.eql(u8, @as([]const u8, @tagName(@typeInfo(@TypeOf(func)))), @as([]const u8, "fn")))
        @compileError("Expected param of type function, but found " ++ @tagName(@typeInfo(@TypeOf(func))) ++ ".");
}

pub fn ReturnType(comptime func: anytype) type {
    expectFunc(func);
    return @typeInfo(@TypeOf(func)).@"fn".return_type.?;
}

pub fn argsOf(comptime func: anytype) []const std.builtin.Type.Fn.Param {
    expectFunc(func);
    return @typeInfo(@TypeOf(func)).@"fn".params;
}

pub fn simpleArgsOf(comptime func: anytype) [@typeInfo(@TypeOf(func)).@"fn".params.len]type {
    expectFunc(func);
    const raw_params = @typeInfo(@TypeOf(func)).@"fn".params;
    var params: [raw_params.len]type = undefined;
    for (raw_params, 0..) |param, i| {
        params[i] = param.type.?;
    }
    return params;
}

pub fn duelTimeFn(comptime ct_fn: anytype, comptime rt_fn: anytype) if (argsOf(rt_fn).len == 0) fn () fn () ReturnType(rt_fn) else fn (if (argsOf(rt_fn).len == 1) simpleArgsOf(rt_fn)[0] else std.meta.Tuple(&simpleArgsOf(rt_fn))) fn () ReturnType(rt_fn) {
    expectFunc(ct_fn);
    expectFunc(rt_fn);
    if (ReturnType(ct_fn) != void) @compileError("Duel time function's comptime fn must return void.");
    const ct_args = simpleArgsOf(ct_fn);
    const rt_args = simpleArgsOf(rt_fn);
    if (ct_args.len != rt_args.len) @compileError("Duel time function's comptime fn and runtime fn must take the same number of args.");
    for (ct_args, 0..) |ct_arg, i|
        if (ct_arg != rt_args[i])
            @compileError("Duel time function's comptime fn and runtime fn must take the same args.");

    const arg_count = argsOf(rt_fn).len;

    if (arg_count == 0)
        return struct {
            fn f() fn () ReturnType(rt_fn) {
                ct_fn();
                return struct {
                    fn f() ReturnType(rt_fn) {
                        rt_fn();
                    }
                }.f;
            }
        }.f;

    if (arg_count == 1)
        return struct {
            fn f(param: simpleArgsOf(rt_fn)[0]) fn () ReturnType(rt_fn) {
                ct_fn(param);
                return struct {
                    fn f() ReturnType(rt_fn) {
                        rt_fn(param);
                    }
                }.f;
            }
        }.f;

    return struct {
        fn f(params: std.meta.Tuple(&simpleArgsOf(rt_fn))) fn () ReturnType(rt_fn) {
            @call(.auto, ct_fn, params);
            return struct {
                fn f() ReturnType(rt_fn) {
                    @call(.auto, rt_fn, params);
                }
            }.f;
        }
    }.f;
}
