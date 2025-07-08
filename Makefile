fmt:
	echo "Formatting lua/deez..."
	stylua lua/ --config-path=.stylua.toml

lint:
	echo "Linting lua/deez..."
	luacheck lua/ --globals vim

pr-ready: fmt lint
