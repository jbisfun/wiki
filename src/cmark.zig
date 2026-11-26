//! The part of cmark-gfm's C API the wiki uses (github/cmark-gfm, compiled in
//! build.zig). Declared by hand: it is small and stable, and this avoids a
//! translate-c step.
pub const Node = opaque {};
pub const Parser = opaque {};
pub const Iter = opaque {};
pub const Extension = opaque {};
pub const Mem = opaque {};

pub const OPT_SOURCEPOS: c_int = 1 << 1;
pub const OPT_UNSAFE: c_int = 1 << 17;
pub const OPT_SMART: c_int = 1 << 10;
pub const OPT_FOOTNOTES: c_int = 1 << 13;
pub const OPT_VALIDATE_UTF8: c_int = 1 << 9;

const BLOCK = 0x8000;
const INLINE = 0x8000 | 0x4000;

pub const NodeType = enum(c_int) {
    none = 0,
    document = BLOCK | 1,
    block_quote = BLOCK | 2,
    list = BLOCK | 3,
    item = BLOCK | 4,
    code_block = BLOCK | 5,
    html_block = BLOCK | 6,
    custom_block = BLOCK | 7,
    paragraph = BLOCK | 8,
    heading = BLOCK | 9,
    thematic_break = BLOCK | 10,
    footnote_definition = BLOCK | 11,
    text = INLINE | 1,
    softbreak = INLINE | 2,
    linebreak = INLINE | 3,
    code = INLINE | 4,
    html_inline = INLINE | 5,
    custom_inline = INLINE | 6,
    emph = INLINE | 7,
    strong = INLINE | 8,
    link = INLINE | 9,
    image = INLINE | 10,
    footnote_reference = INLINE | 11,
    _,
};

pub const BULLET_LIST: c_int = 1;
pub const ORDERED_LIST: c_int = 2;

pub extern fn cmark_gfm_core_extensions_ensure_registered() void;
pub extern fn cmark_find_syntax_extension(name: [*:0]const u8) ?*Extension;
pub extern fn cmark_parser_new(options: c_int) ?*Parser;
pub extern fn cmark_parser_attach_syntax_extension(parser: *Parser, extension: *Extension) c_int;
pub extern fn cmark_parser_feed(parser: *Parser, buffer: [*]const u8, len: usize) void;
pub extern fn cmark_parser_finish(parser: *Parser) ?*Node;
pub extern fn cmark_parser_free(parser: *Parser) void;
pub extern fn cmark_node_free(node: *Node) void;

pub extern fn cmark_node_get_type(node: *Node) NodeType;
pub extern fn cmark_node_get_type_string(node: *Node) [*:0]const u8;
pub extern fn cmark_node_first_child(node: *Node) ?*Node;
pub extern fn cmark_node_last_child(node: *Node) ?*Node;
pub extern fn cmark_node_next(node: *Node) ?*Node;
pub extern fn cmark_node_previous(node: *Node) ?*Node;
pub extern fn cmark_node_parent(node: *Node) ?*Node;
pub extern fn cmark_node_parent_footnote_def(node: *Node) ?*Node;
pub extern fn cmark_node_get_literal(node: *Node) ?[*:0]const u8;
pub extern fn cmark_node_get_url(node: *Node) ?[*:0]const u8;
pub extern fn cmark_node_get_title(node: *Node) ?[*:0]const u8;
pub extern fn cmark_node_get_fence_info(node: *Node) ?[*:0]const u8;
pub extern fn cmark_node_get_heading_level(node: *Node) c_int;
pub extern fn cmark_node_get_list_type(node: *Node) c_int;
pub extern fn cmark_node_get_list_start(node: *Node) c_int;
pub extern fn cmark_node_get_list_tight(node: *Node) c_int;
pub extern fn cmark_node_get_start_line(node: *Node) c_int;
pub extern fn cmark_node_get_start_column(node: *Node) c_int;
pub extern fn cmark_node_get_end_line(node: *Node) c_int;
pub extern fn cmark_node_get_end_column(node: *Node) c_int;
pub extern fn cmark_node_set_literal(node: *Node, content: [*:0]const u8) c_int;
pub extern fn cmark_node_unlink(node: *Node) void;

pub extern fn cmark_gfm_extensions_get_table_columns(node: *Node) u16;
pub extern fn cmark_gfm_extensions_get_table_alignments(node: *Node) ?[*]const u8;
pub extern fn cmark_gfm_extensions_get_table_row_is_header(node: *Node) c_int;
pub extern fn cmark_gfm_extensions_get_tasklist_item_checked(node: *Node) bool;
