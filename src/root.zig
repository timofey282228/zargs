const std = @import("std");

pub fn Argument(comptime T: type) type {
    return struct {
        comptime type: type = T,
        name: []const u8,
        default: ?T = null,
        interrupts_parsing: bool = false,
        parsed_with: ?fn ([]const u8) anyerror!T = null,
    };
}

fn Args(comptime arguments: anytype) type {
    return @Struct(
        .auto,
        null,
        field_names: {
            var names: [arguments.len][]const u8 = undefined;
            for (0.., arguments) |arg_idx, argument| {
                names[arg_idx] = argument.name;
            }
            break :field_names &names;
        },
        field_types: {
            var types: [arguments.len]type = undefined;
            for (0.., arguments) |type_idx, argument| {
                types[type_idx] = argument.type;
            }
            break :field_types &types;
        },
        &@splat(.{}),
    );
}

fn ArgsInParsing(args: type) type {
    const args_struct = @typeInfo(args).@"struct";
    return @Struct(.auto, null, field_names: {
        var names: [args_struct.fields.len][]const u8 = undefined;
        for (0.., args_struct.fields) |arg_idx, field| {
            names[arg_idx] = field.name;
        }
        break :field_names &names;
    }, field_types: {
        var types: [args_struct.fields.len]type = undefined;
        for (0.., args_struct.fields) |type_idx, field| {
            types[type_idx] = ?field.type;
        }
        break :field_types &types;
    }, field_attrs: {
        var attrs: [args_struct.fields.len]std.builtin.Type.StructField.Attributes = undefined;
        for (0.., args_struct.fields) |attr_idx, field| {
            attrs[attr_idx] = .{
                .default_value_ptr = &@as(?field.type, null),
            };
        }
        break :field_attrs &attrs;
    });
}

fn ArgumentParser(comptime configuration: anytype) type {
    const ParsedArgsType = Args(configuration.arguments);
    return struct {
        comptime ParsedArgsType: type = ParsedArgsType,

        pub fn parse_args(_: @This(), args_iterator: *std.process.Args.Iterator) !ParsedArgsType {
            const ArgsInParsingType = ArgsInParsing(ParsedArgsType);
            var args_in_parsing = ArgsInParsingType{};

            argsLoop: while (args_iterator.next()) |arg| {
                inline for (configuration.arguments) |argument| {
                    const name = argument.name;
                    const arg_name = std.mem.cutPrefix(u8, arg, "--") orelse {
                        return error.UnexpectedArgument;
                    };
                    if (std.mem.eql(u8, arg_name, name)) {
                        const arg_value_str = args_iterator.next() orelse {
                            std.debug.print("Missing argument value for {s}\n", .{arg});
                            return error.MissingArgumentValue;
                        };

                        const parsed_arg_value = if (argument.parsed_with) |parser_function|
                            try parser_function(arg_value_str)
                        else
                            try defaultParse(argument.type, arg_value_str);

                        @field(args_in_parsing, name) = parsed_arg_value;
                        if (argument.interrupts_parsing) {
                            break :argsLoop;
                        }
                        continue :argsLoop;
                    }
                }
                std.debug.print("Unknown argument {s}. Known arguments are:\n", .{arg});
                inline for (configuration.arguments) |argument| {
                    std.debug.print("  --{s}\n", .{argument.name});
                }
                return error.UnknownArgument;
            }

            var parsed_args: ParsedArgsType = undefined;
            inline for (configuration.arguments) |argument| {
                if (@field(args_in_parsing, argument.name) == null) {
                    if (argument.default) |default| {
                        @field(parsed_args, argument.name) = default;
                    } else if (@typeInfo(argument.type) == .optional) {
                        @field(parsed_args, argument.name) = null;
                    } else {
                        std.debug.print("Missing argument --{s}\n", .{argument.name});
                        return error.MissingArgument;
                    }
                } else {
                    @field(parsed_args, argument.name) = @field(args_in_parsing, argument.name).?;
                }
            }

            return parsed_args;
        }
    };
}

fn defaultParse(comptime T: type, arg: []const u8) !T {
    switch (@typeInfo(T)) {
        .optional => |t| {
            const parsed = try defaultParse(t.child, arg);
            return parsed;
        },
        .int => {
            if (std.mem.eql(u8, arg[0..@min(2, arg.len)], "0x"))
                return try std.fmt.parseInt(T, arg[2..], 16)
            else if (std.mem.eql(u8, arg[0..@min(2, arg.len)], "0o"))
                return try std.fmt.parseInt(T, arg[2..], 8)
            else if (std.mem.eql(u8, arg[0..@min(2, arg.len)], "0b"))
                return try std.fmt.parseInt(T, arg[2..], 2)
            else
                return try std.fmt.parseInt(T, arg, 10);
        },
        .bool => {
            if (std.mem.eql(u8, arg, "true") or std.mem.eql(u8, arg, "1") or std.mem.eql(u8, arg, "yes"))
                return true;
            if (std.mem.eql(u8, arg, "false") or std.mem.eql(u8, arg, "0") or std.mem.eql(u8, arg, "no"))
                return false;
            return error.InvalidValue;
        },
        .@"enum" => {
            return std.meta.stringToEnum(T, arg) orelse return error.InvalidEnumVariant;
        },
        else => switch (T) {
            []const u8 => return arg,
            else => {},
        },
    }
    @compileLog("Default parser lookup failed for argument type", T);
    @compileError("No default parser for given type");
}

pub fn newArgumentParser(comptime configuration: anytype) ArgumentParser(configuration) {
    return ArgumentParser(configuration){};
}

test "ArgumentParser" {
    const CustomType = enum { variant1, variant2 };
    const parseCustomType = struct {
        pub fn parseCustomType(arg: []const u8) !CustomType {
            _ = arg;
            return .variant2; // pretend this is some custom parsing
        }
    }.parseCustomType;

    var argument_parser = newArgumentParser(.{
        .arguments = &.{
            Argument(u8){
                .name = "u8_arg",
            },
            Argument(usize){
                .name = "usize_arg",
            },
            Argument([]const u8){
                .name = "string_arg",
                .default = "default string",
            },
            Argument(CustomType){
                .name = "custom_arg",
                .default = .variant1,
                .parsed_with = parseCustomType,
            },
            Argument(CustomType){
                .name = "custom_arg2",
                .default = .variant1,
                .parsed_with = parseCustomType,
            },
        },
    });

    var argumets = std.process.Args{
        .vector = &.{
            "--u8_arg",
            "0",
            "--usize_arg",
            "1",
            "--string_arg",
            "string",
            "--custom_arg2",
            "pretend this one is parsed",
        },
    };

    var arguments_iterator = argumets.iterate();
    const args = try argument_parser.parse_args(&arguments_iterator);

    try std.testing.expectEqual(0, args.u8_arg);
    try std.testing.expectEqual(1, args.usize_arg);
    try std.testing.expectEqualSlices(u8, "string", args.string_arg);
    try std.testing.expectEqual(.variant1, args.custom_arg);
    try std.testing.expectEqual(.variant2, args.custom_arg2);
}
