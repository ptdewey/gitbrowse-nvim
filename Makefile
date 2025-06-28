fmt:
	echo "Formatting lua/gitbrowse..."
	stylua lua/ --config-path=.stylua.toml

lint:
	echo "Linting lua/gitbrowse..."
	luacheck lua/ --globals vim

pr-ready: fmt lint
