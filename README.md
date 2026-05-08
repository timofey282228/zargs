# zargs

An absolutely minimal named argument parser for when you just want to turn `--this and --that string` into a

```zig
const args = Args{
  .this: "and",
  .that: .string
}
```

by the means of

```zig
const std = @import("std");
const zargs = @import("zargs");

const That = enum { string, other };

pub fn main(init: std.process.Init) !void {
    var argument_parser = zargs.newArgumentParser(
        .{
            .arguments = &.{
                zargs.Argument([]const u8){
                    .name = "this",
                },
                zargs.Argument(That){
                    .name = "that",
                    .default = .other,
                },
            },
        },
    );

    const arguments = init.minimal.args;
    var arguments_iterator = arguments.iterate();
    _ = arguments_iterator.skip();
    const args = try argument_parser.parse_args(&arguments_iterator);

    std.debug.print("Parsed: {any}\n", .{args});

    const Args = argument_parser.ParsedArgsType;
    const expected_args = Args{ .this = "and", .that = .string };

    try std.testing.expectEqualDeep(expected_args, args);
    std.debug.print("As expected\n", .{});
}
```
