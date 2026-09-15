(meta_ident) @editor.syntax.assemblyarm.keyword

(label (ident) @editor.syntax.assemblyarm.name.partial)
(label (meta_ident) @editor.syntax.assemblyarm.name.partial)

(instruction kind: (word) @editor.syntax.assemblyarm.identifier)
(reg) @editor.syntax.assemblyarm.identifier

[(int) (float)] @editor.syntax.assemblyarm.number
(string) @editor.syntax.assemblyarm.string

[(line_comment) (block_comment)] @editor.syntax.assemblyarm.comment
