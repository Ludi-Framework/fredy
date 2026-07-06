mod config;
mod connection;
mod runtime;
mod transaction;
mod values;

use mlua::prelude::*;

#[mlua::lua_module]
fn fredy_core(lua: &Lua) -> LuaResult<LuaTable> {
    sqlx::any::install_default_drivers();

    let exports = lua.create_table()?;
    exports.set("connect", lua.create_function(connection::connect)?)?;
    exports.set("NULL", lua.create_userdata(values::NullSentinel)?)?;
    Ok(exports)
}
