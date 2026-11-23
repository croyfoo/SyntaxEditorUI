; Remapped from tree-sitter-grammars/tree-sitter-lua v0.5.0 queries/highlights.scm
; into this package's editor.syntax.<language>.<kind> capture scheme.

[
  "return" "goto" "in" "local" "global" "do" "end" "while" "repeat" "until"
  "if" "elseif" "else" "then" "for" "function" "and" "not" "or"
] @editor.syntax.lua.keyword

(break_statement) @editor.syntax.lua.keyword

((identifier) @editor.syntax.lua.identifier.variable.system
  (#eq? @editor.syntax.lua.identifier.variable.system "self"))

(variable_list
  (attribute
    (identifier) @editor.syntax.lua.attribute))

((identifier) @editor.syntax.lua.identifier.constant
  (#match? @editor.syntax.lua.identifier.constant "^[A-Z][A-Z_0-9]*$"))

(vararg_expression) @editor.syntax.lua.identifier.constant

[
  (nil)
  (false)
  (true)
] @editor.syntax.lua.keyword

(function_declaration
  name: [
    (identifier) @editor.syntax.lua.identifier.function
    (dot_index_expression
      field: (identifier) @editor.syntax.lua.identifier.function)
    (method_index_expression
      method: (identifier) @editor.syntax.lua.identifier.function)
  ])

(function_call
  name: [
    (identifier) @editor.syntax.lua.identifier.function
    (dot_index_expression
      field: (identifier) @editor.syntax.lua.identifier.function)
    (method_index_expression
      method: (identifier) @editor.syntax.lua.identifier.function)
  ])

(function_call
  (identifier) @editor.syntax.lua.identifier.function.system
  (#any-of? @editor.syntax.lua.identifier.function.system
    "assert" "collectgarbage" "dofile" "error" "getfenv" "getmetatable" "ipairs" "load" "loadfile"
    "loadstring" "module" "next" "pairs" "pcall" "print" "rawequal" "rawget" "rawset" "require"
    "select" "setfenv" "setmetatable" "tonumber" "tostring" "type" "unpack" "xpcall"))

(comment) @editor.syntax.lua.comment

(hash_bang_line) @editor.syntax.lua.preprocessor

(number) @editor.syntax.lua.number

(string) @editor.syntax.lua.string
