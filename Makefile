# Local development without luarocks. Builds the native module for the
# chosen Lua and symlinks it next to the Lua sources so require() finds it.
#
#   make dev              # build for Lua 5.4
#   make dev LUA=luajit   # build for LuaJIT
#   make test             # cargo test + busted

LUA ?= lua54
LUA_BIN ?= lua5.4

dev:
	cargo build --release --features $(LUA)
	ln -sf target/release/libfredy_core.so fredy_core.so

test: dev
	cargo test --features $(LUA)
	busted

.PHONY: dev test
