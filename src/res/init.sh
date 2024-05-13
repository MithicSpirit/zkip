cd() {{
	local target
	target="$('{[exe]s}' cd "$@")" || return 1
	command cd "$target" || return 1
	if type '{[name]s}_hook' >/dev/null 2>/dev/null; then
		'{[name]s}_hook'
	fi
	'{[exe]s}' '&' visit || :
}}
'{[exe]s}' '&' visit || :
