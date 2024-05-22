const std = @import("std");

const jetzig = @import("../../jetzig.zig");

const Route = @This();

pub const Action = enum { index, get, post, put, patch, delete, custom };
pub const RenderFn = *const fn (Route, *jetzig.http.Request) anyerror!jetzig.views.View;
pub const RenderStaticFn = *const fn (Route, *jetzig.http.StaticRequest) anyerror!jetzig.views.View;

pub const ViewWithoutId = *const fn (*jetzig.http.Request, *jetzig.data.Data) anyerror!jetzig.views.View;
pub const ViewWithId = *const fn (id: []const u8, *jetzig.http.Request, *jetzig.data.Data) anyerror!jetzig.views.View;
const StaticViewWithoutId = *const fn (*jetzig.http.StaticRequest, *jetzig.data.Data) anyerror!jetzig.views.View;
const StaticViewWithId = *const fn (id: []const u8, *jetzig.http.StaticRequest, *jetzig.data.Data) anyerror!jetzig.views.View;

pub const DynamicViewType = union(Action) {
    index: ViewWithoutId,
    get: ViewWithId,
    post: ViewWithoutId,
    put: ViewWithId,
    patch: ViewWithId,
    delete: ViewWithId,
    custom: CustomViewType,
};

pub const StaticViewType = union(Action) {
    index: StaticViewWithoutId,
    get: StaticViewWithId,
    post: StaticViewWithoutId,
    put: StaticViewWithId,
    patch: StaticViewWithId,
    delete: StaticViewWithId,
    custom: void,
};

pub const CustomViewType = union(enum) {
    with_id: ViewWithId,
    without_id: ViewWithoutId,
};

pub const ViewType = union(enum) {
    static: StaticViewType,
    dynamic: DynamicViewType,
    custom: CustomViewType,
};

name: []const u8,
action: Action,
method: jetzig.http.Request.Method = undefined, // Used by custom routes only
view_name: []const u8,
uri_path: []const u8,
view: ViewType,
render: RenderFn = renderFn,
renderStatic: RenderStaticFn = renderStaticFn,
static: bool = false,
layout: ?[]const u8 = null,
template: []const u8,
json_params: []const []const u8,
params: std.ArrayList(*jetzig.data.Data) = undefined,

/// Initializes a route's static params on server launch. Converts static params (JSON strings)
/// to `jetzig.data.Data` values. Memory is owned by caller (`App.start()`).
pub fn initParams(self: *Route, allocator: std.mem.Allocator) !void {
    self.params = std.ArrayList(*jetzig.data.Data).init(allocator);
    for (self.json_params) |params| {
        var data = try allocator.create(jetzig.data.Data);
        data.* = jetzig.data.Data.init(allocator);
        try self.params.append(data);
        try data.fromJson(params);
    }
}

pub fn deinitParams(self: *const Route) void {
    for (self.params.items) |data| {
        data.deinit();
        data.parent_allocator.destroy(data);
    }
    self.params.deinit();
}

/// Match a **custom** route to a request - not used by auto-generated route matching.
pub fn match(self: Route, request: *const jetzig.http.Request) bool {
    if (self.method != request.method) return false;

    var request_path_it = std.mem.splitScalar(u8, request.path.base_path, '/');
    var uri_path_it = std.mem.splitScalar(u8, self.uri_path, '/');

    while (uri_path_it.next()) |expected_segment| {
        const actual_segment = request_path_it.next() orelse return false;
        if (std.mem.startsWith(u8, expected_segment, ":")) continue;
        if (!std.mem.eql(u8, expected_segment, actual_segment)) return false;
    }

    return true;
}

fn renderFn(self: Route, request: *jetzig.http.Request) anyerror!jetzig.views.View {
    switch (self.view) {
        .dynamic => {},
        .custom => |view_type| switch (view_type) {
            .with_id => |view| return try view(request.path.resourceId(self), request, request.response_data),
            .without_id => |view| return try view(request, request.response_data),
        },
        // We only end up here if a static route is defined but its output is not found in the
        // file system (e.g. if it was manually deleted after build). This should be avoidable by
        // including the content as an artifact in the compiled executable (TODO):
        .static => return error.JetzigMissingStaticContent,
    }

    switch (self.view.dynamic) {
        .index => |view| return try view(request, request.response_data),
        .get => |view| return try view(request.path.resource_id, request, request.response_data),
        .post => |view| return try view(request, request.response_data),
        .patch => |view| return try view(request.path.resource_id, request, request.response_data),
        .put => |view| return try view(request.path.resource_id, request, request.response_data),
        .delete => |view| return try view(request.path.resource_id, request, request.response_data),
        .custom => unreachable,
    }
}

fn renderStaticFn(self: Route, request: *jetzig.http.StaticRequest) anyerror!jetzig.views.View {
    request.response_data.* = jetzig.data.Data.init(request.allocator);

    switch (self.view.static) {
        .index => |view| return try view(request, request.response_data),
        .get => |view| return try view(try request.resourceId(), request, request.response_data),
        .post => |view| return try view(request, request.response_data),
        .patch => |view| return try view(try request.resourceId(), request, request.response_data),
        .put => |view| return try view(try request.resourceId(), request, request.response_data),
        .delete => |view| return try view(try request.resourceId(), request, request.response_data),
        .custom => unreachable,
    }
}
