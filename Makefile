# Local development without luarocks. Builds the native module for the
# chosen Lua and symlinks it next to the Lua sources so require() finds it.
#
#   make dev              # build for Lua 5.4
#   make dev LUA=luajit   # build for LuaJIT
#   make test             # cargo test + busted

LUA ?= lua54
LUA_BIN ?= lua5.4

# The cdylib name and the dynamic-loader extension differ per platform:
# Lua loads C modules as `fredy_core.so` on Linux/macOS and `fredy_core.dll`
# on Windows, while cargo emits `libfredy_core.{so,dylib}` / `fredy_core.dll`.
# On Windows a symlink needs privileges, so copy the artifact instead.
ifeq ($(OS),Windows_NT)
	CORE := target/release/fredy_core.dll
	MODULE := fredy_core.dll
	LINK := cp -f
else
	MODULE := fredy_core.so
	LINK := ln -sf
	ifeq ($(shell uname -s),Darwin)
		CORE := target/release/libfredy_core.dylib
	else
		CORE := target/release/libfredy_core.so
	endif
endif

dev:
	cargo build --release --features $(LUA)
	$(LINK) $(CORE) $(MODULE)

test: dev
	cargo test --features $(LUA)
	busted

# Format Rust (rustfmt) and Lua (stylua) sources in place.
fmt:
	cargo fmt
	stylua fredy/ spec/ examples/

# Verify formatting without writing; fails if anything is out of style.
fmt-check:
	cargo fmt --check
	stylua --check fredy/ spec/ examples/

.PHONY: dev test fmt fmt-check
