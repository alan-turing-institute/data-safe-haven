all
exclude_rule 'MD002' # this conflicts with the use of partial Markdown snippets
rule 'MD003', :style => :atx
rule 'MD004', :style => :dash
rule 'MD007', :indent => 4
exclude_rule 'MD013'
exclude_rule 'MD024'
rule 'MD026', :punctuation => ".,;"
rule 'MD029', :style => :one
exclude_rule 'MD033'
exclude_rule 'MD034'
exclude_rule 'MD041' # this conflicts with MyST target anchors
