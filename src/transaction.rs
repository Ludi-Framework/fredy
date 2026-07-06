//! Transaction handle passed to the Lua callback of db:transaction().
//! Owns the pooled connection while the transaction is open; the
//! connection module takes it back to COMMIT/ROLLBACK.

use std::cell::RefCell;

use mlua::prelude::*;
use sqlx::Any;
use sqlx::pool::PoolConnection;

use crate::runtime::RT;
use crate::values::{bind_params, rows_to_lua};

pub struct Transaction {
    conn: RefCell<Option<PoolConnection<Any>>>,
}

impl Transaction {
    pub fn new(conn: PoolConnection<Any>) -> Self {
        Transaction {
            conn: RefCell::new(Some(conn)),
        }
    }

    /// Removes the connection, leaving the handle unusable ("already
    /// finished" errors on any further use).
    pub fn take(&self) -> Option<PoolConnection<Any>> {
        self.conn.borrow_mut().take()
    }

    fn with_conn<R>(
        &self,
        f: impl FnOnce(&mut PoolConnection<Any>) -> LuaResult<R>,
    ) -> LuaResult<R> {
        let mut guard = self.conn.borrow_mut();
        let conn = guard
            .as_mut()
            .ok_or_else(|| LuaError::external("transaction already finished"))?;
        f(conn)
    }
}

impl LuaUserData for Transaction {
    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        methods.add_method(
            "query",
            |lua, this, (sql, params): (String, Option<LuaTable>)| {
                this.with_conn(|conn| {
                    let mut query = sqlx::query(&sql);
                    if let Some(params) = &params {
                        query = bind_params(query, params)?;
                    }
                    let rows = RT
                        .block_on(query.fetch_all(&mut **conn))
                        .map_err(LuaError::external)?;
                    rows_to_lua(lua, rows)
                })
            },
        );

        methods.add_method(
            "execute",
            |_, this, (sql, params): (String, Option<LuaTable>)| {
                this.with_conn(|conn| {
                    let mut query = sqlx::query(&sql);
                    if let Some(params) = &params {
                        query = bind_params(query, params)?;
                    }
                    let result = RT
                        .block_on(query.execute(&mut **conn))
                        .map_err(LuaError::external)?;
                    Ok(result.rows_affected() as i64)
                })
            },
        );
    }
}
