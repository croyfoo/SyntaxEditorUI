; Inject the markdown-inline grammar into inline content, so emphasis, links,
; and code spans are highlighted. Uses a static `#set!` directive (the only
; injection form this package's layered highlighter supports); the dynamic
; per-node capture form is deliberately avoided. Fenced-code-block language
; injection is likewise omitted, as it requires that unsupported dynamic form.
((inline) @injection.content
 (#set! injection.language "markdown-inline"))
