; Source:
; - tree-sitter-grammars/tree-sitter-objc @ 181a81b8f23a2d593e7ab4259981f50122909fda
; Upstream inherits `c`; the only Objective-C-specific entries are commented placeholders.
;
; TODO(amaanq): uncomment/add when upstream adds asm support.
; (ms_asm_block "{" _ @asm "}")
;
; ((asm_specifier (string_literal) @asm)
;   (#offset! @asm 0 1 0 -1))
;
; ((asm_statement (string_literal) @asm)
;   (#offset! @asm 0 1 0 -1))
