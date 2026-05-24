; Combined locally because SyntaxEditorUI's SwiftTreeSitter integration does not
; resolve `; inherits:` directives.
; Sources:
; - tree-sitter/tree-sitter-c @ ae19b676b13bdcc13b7665397e6d9b14975473dd
; - tree-sitter-grammars/tree-sitter-objc @ 181a81b8f23a2d593e7ab4259981f50122909fda

(identifier) @editor.syntax.objectivec.identifier

"break" @editor.syntax.objectivec.keyword
"case" @editor.syntax.objectivec.keyword
"const" @editor.syntax.objectivec.keyword
"continue" @editor.syntax.objectivec.keyword
"default" @editor.syntax.objectivec.keyword
"do" @editor.syntax.objectivec.keyword
"else" @editor.syntax.objectivec.keyword
"enum" @editor.syntax.objectivec.keyword
"extern" @editor.syntax.objectivec.keyword
"for" @editor.syntax.objectivec.keyword
"if" @editor.syntax.objectivec.keyword
"inline" @editor.syntax.objectivec.keyword
"return" @editor.syntax.objectivec.keyword
"sizeof" @editor.syntax.objectivec.keyword
"static" @editor.syntax.objectivec.keyword
"struct" @editor.syntax.objectivec.keyword
"switch" @editor.syntax.objectivec.keyword
"typedef" @editor.syntax.objectivec.keyword
"union" @editor.syntax.objectivec.keyword
"volatile" @editor.syntax.objectivec.keyword
"while" @editor.syntax.objectivec.keyword

((identifier) @editor.syntax.objectivec.keyword
  (#any-of? @editor.syntax.objectivec.keyword
    "BOOL"
    "Class"
    "FALSE"
    "IMP"
    "NO"
    "NULL"
    "SEL"
    "TRUE"
    "YES"
    "_cmd"
    "bycopy"
    "byref"
    "id"
    "inout"
    "instancetype"
    "nonnull"
    "nullable"
    "null_unspecified"
    "out"
    "self"
    "super"))

; BEGIN GENERATED EDITOR SYNTAX WORDS: objectivec-preprocessor-keywords
[
  "#define"
  "#elif"
  "#else"
  "#endif"
  "#if"
  "#ifdef"
  "#ifndef"
  "#undef"
] @editor.syntax.objectivec.preprocessor.keyword
; END GENERATED EDITOR SYNTAX WORDS: objectivec-preprocessor-keywords

(preproc_directive) @editor.syntax.objectivec.preprocessor.keyword

"--" @editor.syntax.objectivec.plain
"-" @editor.syntax.objectivec.plain
"-=" @editor.syntax.objectivec.plain
"->" @editor.syntax.objectivec.plain
"=" @editor.syntax.objectivec.plain
"!=" @editor.syntax.objectivec.plain
"*" @editor.syntax.objectivec.plain
"&" @editor.syntax.objectivec.plain
"&&" @editor.syntax.objectivec.plain
"+" @editor.syntax.objectivec.plain
"++" @editor.syntax.objectivec.plain
"+=" @editor.syntax.objectivec.plain
"<" @editor.syntax.objectivec.plain
"==" @editor.syntax.objectivec.plain
">" @editor.syntax.objectivec.plain
"||" @editor.syntax.objectivec.plain

"." @editor.syntax.objectivec.plain
";" @editor.syntax.objectivec.plain

(string_literal) @editor.syntax.objectivec.string
(system_lib_string) @editor.syntax.objectivec.string

(null) @editor.syntax.objectivec.keyword
(number_literal) @editor.syntax.objectivec.number
(char_literal) @editor.syntax.objectivec.number

(field_identifier) @editor.syntax.objectivec.identifier
(statement_identifier) @editor.syntax.objectivec.identifier
(type_identifier) @editor.syntax.objectivec.identifier
(primitive_type) @editor.syntax.objectivec.keyword
(sized_type_specifier) @editor.syntax.objectivec.keyword
(storage_class_specifier) @editor.syntax.objectivec.keyword
(typedefed_specifier) @editor.syntax.objectivec.keyword

((function_definition
  type: (type_identifier) @editor.syntax.objectivec.keyword)
  (#eq? @editor.syntax.objectivec.keyword "typedef"))

(comment) @editor.syntax.objectivec.comment

; Preprocs

(preproc_def) @editor.syntax.objectivec.preprocessor
(preproc_function_def) @editor.syntax.objectivec.preprocessor
(preproc_call) @editor.syntax.objectivec.preprocessor
(preproc_linemarker) @editor.syntax.objectivec.preprocessor

(preproc_def
  name: (identifier) @editor.syntax.objectivec.preprocessor.define)
(preproc_function_def
  name: (identifier) @editor.syntax.objectivec.preprocessor.define
  parameters: (preproc_params) @editor.syntax.objectivec.preprocessor)
(preproc_undef
  name: (_) @editor.syntax.objectivec.preprocessor.identifier) @editor.syntax.objectivec.preprocessor
(preproc_ifdef
  name: (identifier) @editor.syntax.objectivec.preprocessor.identifier)
(preproc_elifdef
  name: (identifier) @editor.syntax.objectivec.preprocessor.identifier)
(preproc_defined
  (identifier) @editor.syntax.objectivec.preprocessor.identifier)

; BEGIN GENERATED EDITOR SYNTAX WORDS: objectivec-attributes
[
  "@autoreleasepool"
  "@catch"
  "@compatibility_alias"
  "@defs"
  "@dynamic"
  "@end"
  "@finally"
  "@implementation"
  "@interface"
  "@optional"
  "@property"
  "@protocol"
  "@required"
  "@selector"
  "@synchronized"
  "@synthesize"
  "@throw"
  "@try"
] @editor.syntax.objectivec.keyword
; END GENERATED EDITOR SYNTAX WORDS: objectivec-attributes

; Includes

(module_import "@import" @editor.syntax.objectivec.preprocessor path: (identifier) @editor.syntax.objectivec.identifier)

((preproc_include
  _ @editor.syntax.objectivec.preprocessor path: (_))
  (#any-of? @editor.syntax.objectivec.preprocessor "#include" "#import"))

; Type Qualifiers

[
  "__covariant"
  "__contravariant"
  (visibility_specification)
] @editor.syntax.objectivec.keyword

; Storageclasses

[
  "volatile"
  (protocol_qualifier)
] @editor.syntax.objectivec.keyword

; Keywords

[
  "availability"
] @editor.syntax.objectivec.keyword

(class_declaration "@" @editor.syntax.objectivec.keyword "class" @editor.syntax.objectivec.keyword)

(method_definition ["+" "-"] @editor.syntax.objectivec.plain)
(method_declaration ["+" "-"] @editor.syntax.objectivec.plain)

[
  "__typeof__"
  "__typeof"
  "typeof"
  "in"
] @editor.syntax.objectivec.keyword

[
  "oneway"
] @editor.syntax.objectivec.keyword

; Exceptions

[
  "__try"
  "__catch"
  "__finally"
] @editor.syntax.objectivec.keyword

; Functions & Methods

[
  "objc_bridge_related"
  "@available"
  "__builtin_available"
  "va_arg"
  "asm"
] @editor.syntax.objectivec.identifier

(method_definition (identifier) @editor.syntax.objectivec.identifier)

(method_declaration (identifier) @editor.syntax.objectivec.identifier)

(method_identifier (identifier)? @editor.syntax.objectivec.identifier ":" @editor.syntax.objectivec.plain (identifier)? @editor.syntax.objectivec.identifier)

(message_expression method: (identifier) @editor.syntax.objectivec.identifier)

; Attributes

(availability_attribute_specifier
  [
    "CF_FORMAT_FUNCTION" "NS_AVAILABLE" "__IOS_AVAILABLE" "NS_AVAILABLE_IOS"
    "API_AVAILABLE" "API_UNAVAILABLE" "API_DEPRECATED" "NS_ENUM_AVAILABLE_IOS"
    "NS_DEPRECATED_IOS" "NS_ENUM_DEPRECATED_IOS" "NS_FORMAT_FUNCTION" "DEPRECATED_MSG_ATTRIBUTE"
    "__deprecated_msg" "__deprecated_enum_msg" "NS_SWIFT_NAME" "NS_SWIFT_UNAVAILABLE"
    "NS_EXTENSION_UNAVAILABLE_IOS" "NS_CLASS_AVAILABLE_IOS" "NS_CLASS_DEPRECATED_IOS" "__OSX_AVAILABLE_STARTING"
    "NS_ROOT_CLASS" "NS_UNAVAILABLE" "NS_REQUIRES_NIL_TERMINATION" "CF_RETURNS_RETAINED"
    "CF_RETURNS_NOT_RETAINED" "DEPRECATED_ATTRIBUTE" "UI_APPEARANCE_SELECTOR" "UNAVAILABLE_ATTRIBUTE"
  ] @editor.syntax.objectivec.identifier)

; Macros

(type_qualifier
  [
    "_Complex"
    "_Nonnull"
    "_Nullable"
    "_Nullable_result"
    "_Null_unspecified"
    "__autoreleasing"
    "__block"
    "__bridge"
    "__bridge_retained"
    "__bridge_transfer"
    "__complex"
    "__kindof"
    "__nonnull"
    "__nullable"
    "__ptrauth_objc_class_ro"
    "__ptrauth_objc_isa_pointer"
    "__ptrauth_objc_super_pointer"
    "__strong"
    "__thread"
    "__unsafe_unretained"
    "__unused"
    "__weak"
  ]) @editor.syntax.objectivec.preprocessor

[ "__real" "__imag" ] @editor.syntax.objectivec.preprocessor

((call_expression function: (identifier) @editor.syntax.objectivec.preprocessor)
  (#eq? @editor.syntax.objectivec.preprocessor "testassert"))

; Types

(class_declaration (identifier) @editor.syntax.objectivec.identifier)

(class_interface "@interface" . (identifier) @editor.syntax.objectivec.identifier superclass: _? @editor.syntax.objectivec.identifier category: _? @editor.syntax.objectivec.identifier)

(class_implementation "@implementation" . (identifier) @editor.syntax.objectivec.identifier superclass: _? @editor.syntax.objectivec.identifier category: _? @editor.syntax.objectivec.identifier)

(protocol_forward_declaration (identifier) @editor.syntax.objectivec.identifier)

(protocol_reference_list (identifier) @editor.syntax.objectivec.identifier)

; Constants

(property_attribute . (identifier) @editor.syntax.objectivec.keyword)

[ "__asm" "__asm__" ] @editor.syntax.objectivec.preprocessor

; Properties

(property_implementation "@synthesize" (identifier) @editor.syntax.objectivec.identifier)

; Parameters

(method_parameter ":" @editor.syntax.objectivec.plain (identifier) @editor.syntax.objectivec.identifier)

(method_parameter declarator: (identifier) @editor.syntax.objectivec.identifier)

(parameter_declaration
  declarator: (function_declarator
                declarator: (parenthesized_declarator
                              (block_pointer_declarator
                                declarator: (identifier) @editor.syntax.objectivec.identifier))))

"..." @editor.syntax.objectivec.plain

; Operators

[
  "^"
] @editor.syntax.objectivec.plain

; Literals

(platform) @editor.syntax.objectivec.string

(version_number) @editor.syntax.objectivec.url @editor.syntax.objectivec.number

[ "<" ">" ] @editor.syntax.objectivec.plain
