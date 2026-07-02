; Remapped from tree-sitter-php v0.24.2 queries/highlights.scm into this
; package's editor.syntax.<language>.<kind> capture scheme (standard
; tree-sitter capture names are treated as plain text by the highlighter).

[
  (php_tag)
  (php_end_tag)
] @editor.syntax.php.preprocessor

; Keywords

[
  "and"
  "as"
  "break"
  "case"
  "catch"
  "class"
  "clone"
  "const"
  "continue"
  "declare"
  "default"
  "do"
  "echo"
  "else"
  "elseif"
  "enddeclare"
  "endfor"
  "endforeach"
  "endif"
  "endswitch"
  "endwhile"
  "enum"
  "exit"
  "extends"
  "finally"
  "fn"
  "for"
  "foreach"
  "function"
  "global"
  "goto"
  "if"
  "implements"
  "include"
  "include_once"
  "instanceof"
  "insteadof"
  "interface"
  "match"
  "namespace"
  "new"
  "or"
  "print"
  "require"
  "require_once"
  "return"
  "switch"
  "throw"
  "trait"
  "try"
  "use"
  "while"
  "xor"
  "yield"
  "yield from"
  (abstract_modifier)
  (final_modifier)
  (readonly_modifier)
  (static_modifier)
  (visibility_modifier)
] @editor.syntax.php.keyword

(function_static_declaration "static" @editor.syntax.php.keyword)

; Namespace

(namespace_definition
  name: (namespace_name
    (name) @editor.syntax.php.identifier))

(namespace_name
  (name) @editor.syntax.php.identifier)

(namespace_use_clause
  [
    (name) @editor.syntax.php.identifier.type
    (qualified_name
      (name) @editor.syntax.php.identifier.type)
    alias: (name) @editor.syntax.php.identifier.type
  ])

(namespace_use_clause
  type: "function"
  [
    (name) @editor.syntax.php.identifier.function
    (qualified_name
      (name) @editor.syntax.php.identifier.function)
    alias: (name) @editor.syntax.php.identifier.function
  ])

(namespace_use_clause
  type: "const"
  [
    (name) @editor.syntax.php.identifier.constant
    (qualified_name
      (name) @editor.syntax.php.identifier.constant)
    alias: (name) @editor.syntax.php.identifier.constant
  ])

(relative_name "namespace" @editor.syntax.php.identifier)

; Variables

(relative_scope) @editor.syntax.php.identifier.variable.system

(variable_name) @editor.syntax.php.identifier.variable

(method_declaration name: (name) @editor.syntax.php.identifier.type
  (#eq? @editor.syntax.php.identifier.type "__construct"))

(object_creation_expression [
  (name) @editor.syntax.php.identifier.type
  (qualified_name (name) @editor.syntax.php.identifier.type)
  (relative_name (name) @editor.syntax.php.identifier.type)
])

((name) @editor.syntax.php.identifier.constant
 (#match? @editor.syntax.php.identifier.constant "^_?[A-Z][A-Z\\d_]+$"))
((name) @editor.syntax.php.identifier.constant.system
 (#match? @editor.syntax.php.identifier.constant.system "^__[A-Z][A-Z\d_]+__$"))
(const_declaration (const_element (name) @editor.syntax.php.identifier.constant))

; Types

(primitive_type) @editor.syntax.php.identifier.type.system
(cast_type) @editor.syntax.php.identifier.type.system
(named_type [
  (name) @editor.syntax.php.identifier.type
  (qualified_name (name) @editor.syntax.php.identifier.type)
  (relative_name (name) @editor.syntax.php.identifier.type)
]) @editor.syntax.php.identifier.type
(named_type (name) @editor.syntax.php.identifier.type.system
  (#any-of? @editor.syntax.php.identifier.type.system "static" "self"))

(scoped_call_expression
  scope: [
    (name) @editor.syntax.php.identifier.type
    (qualified_name (name) @editor.syntax.php.identifier.type)
    (relative_name (name) @editor.syntax.php.identifier.type)
  ])

; Functions

(array_creation_expression "array" @editor.syntax.php.identifier.function.system)
(list_literal "list" @editor.syntax.php.identifier.function.system)
(exit_statement "exit" @editor.syntax.php.identifier.function.system "(")

(method_declaration
  name: (name) @editor.syntax.php.identifier.function)

(function_call_expression
  function: [
    (qualified_name (name))
    (relative_name (name))
    (name)
  ] @editor.syntax.php.identifier.function)

(scoped_call_expression
  name: (name) @editor.syntax.php.identifier.function)

(member_call_expression
  name: (name) @editor.syntax.php.identifier.function)

(function_definition
  name: (name) @editor.syntax.php.identifier.function)

; Member

(property_element
  (variable_name) @editor.syntax.php.identifier.variable)

(member_access_expression
  name: (variable_name (name)) @editor.syntax.php.identifier.variable)
(member_access_expression
  name: (name) @editor.syntax.php.identifier.variable)

; Basic tokens
[
  (string)
  (string_content)
  (encapsed_string)
  (heredoc)
  (heredoc_body)
  (nowdoc_body)
] @editor.syntax.php.string
(boolean) @editor.syntax.php.identifier.constant.system
(null) @editor.syntax.php.identifier.constant.system
(integer) @editor.syntax.php.number
(float) @editor.syntax.php.number
(comment) @editor.syntax.php.comment

((name) @editor.syntax.php.identifier.variable.system
 (#eq? @editor.syntax.php.identifier.variable.system "this"))

