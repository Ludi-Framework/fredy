//! Conversions between Lua values and SQL values.

use mlua::prelude::*;
use sqlx::any::{AnyArguments, AnyRow};
use sqlx::query::Query;
use sqlx::{Any, Column, Row, ValueRef};

/// Marker userdata exposed as `fredy.NULL`. Required for SQL NULL in
/// parameter lists because a `nil` inside a Lua table simply vanishes —
/// see docs/adr/0003-null-handling.md.
pub struct NullSentinel;

impl LuaUserData for NullSentinel {}

type AnyQuery<'q> = Query<'q, Any, AnyArguments<'q>>;

/// Length of the parameter list as the highest integer key present.
/// `#t`/raw_len are undefined on tables with nil holes, and a hole that
/// goes unnoticed silently drops a parameter — so scan the real keys and
/// let the nil check below catch holes deterministically on every Lua.
fn params_len(params: &LuaTable) -> LuaResult<usize> {
    let mut max = 0usize;
    params.for_each(|key: LuaValue, _: LuaValue| {
        if let LuaValue::Integer(i) = key {
            if i > 0 && i as usize > max {
                max = i as usize;
            }
        }
        Ok(())
    })?;
    Ok(max)
}

pub fn bind_params<'q>(mut query: AnyQuery<'q>, params: &LuaTable) -> LuaResult<AnyQuery<'q>> {
    for i in 1..=params_len(params)? {
        let value: LuaValue = params.raw_get(i)?;
        query = match value {
            LuaValue::Boolean(b) => query.bind(b),
            LuaValue::Integer(n) => query.bind(n),
            LuaValue::Number(n) => query.bind(n),
            LuaValue::String(s) => query.bind(s.to_str()?.to_owned()),
            LuaValue::UserData(ud) if ud.is::<NullSentinel>() => query.bind(None::<String>),
            LuaValue::Nil => {
                return Err(LuaError::external(format!(
                    "parameter #{i} is nil; use fredy.NULL for SQL NULL"
                )));
            }
            other => {
                return Err(LuaError::external(format!(
                    "parameter #{i} has unsupported type '{}'",
                    other.type_name()
                )));
            }
        };
    }
    Ok(query)
}

pub fn rows_to_lua(lua: &Lua, rows: Vec<AnyRow>) -> LuaResult<LuaTable> {
    let out = lua.create_table_with_capacity(rows.len(), 0)?;
    for (i, row) in rows.iter().enumerate() {
        out.raw_set(i + 1, row_to_lua(lua, row)?)?;
    }
    Ok(out)
}

/// SQL NULL becomes `nil` (the column is simply absent from the row
/// table). Integers stay integers; SQLite has no boolean type, so
/// booleans come back as 0/1 there.
fn row_to_lua(lua: &Lua, row: &AnyRow) -> LuaResult<LuaTable> {
    let out = lua.create_table()?;

    for (i, column) in row.columns().iter().enumerate() {
        let raw = row.try_get_raw(i).map_err(LuaError::external)?;
        if raw.is_null() {
            continue;
        }

        let value: LuaValue = if let Ok(v) = row.try_get::<i64, _>(i) {
            LuaValue::Integer(v)
        } else if let Ok(v) = row.try_get::<f64, _>(i) {
            LuaValue::Number(v)
        } else if let Ok(v) = row.try_get::<bool, _>(i) {
            LuaValue::Boolean(v)
        } else if let Ok(v) = row.try_get::<String, _>(i) {
            LuaValue::String(lua.create_string(&v)?)
        } else {
            LuaValue::Nil
        };

        out.set(column.name(), value)?;
    }

    Ok(out)
}
