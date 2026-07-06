use std::cell::RefCell;

use mlua::prelude::*;
use sqlx::any::AnyPoolOptions;
use sqlx::pool::PoolConnection;
use sqlx::{Any, AnyPool};

use crate::runtime::RT;
use crate::values::{bind_params, row_to_lua};

pub struct Connection {
    pool: AnyPool,
}

pub struct Transaction {
    conn: RefCell<Option<PoolConnection<Any>>>,
}

fn build_url(
    adapter: &str,
    url: Option<String>,
    path: Option<String>,
) -> Result<String, String> {
    match adapter {
        "postgres" => url.ok_or_else(|| "postgres adapter requires 'url'".to_string()),
        "sqlite" => {
            let path = path.ok_or_else(|| "sqlite adapter requires 'path'".to_string())?;
            if path == ":memory:" {
                Ok("sqlite::memory:".to_string())
            } else {
                Ok(format!("sqlite://{path}?mode=rwc"))
            }
        }
        other => Err(format!(
            "unknown adapter '{other}' (supported: postgres, sqlite)"
        )),
    }
}

/// A pooled in-memory SQLite gives every connection its own private
/// database; force a single connection so the data is actually shared.
fn effective_max_connections(url: &str, requested: Option<u32>) -> u32 {
    if url == "sqlite::memory:" {
        1
    } else {
        requested.unwrap_or(5)
    }
}

pub fn connect(_lua: &Lua, opts: LuaTable) -> LuaResult<Connection> {
    let adapter: String = opts.get("adapter")?;

    let url = build_url(
        &adapter,
        opts.get::<Option<String>>("url")?,
        opts.get::<Option<String>>("path")?,
    )
    .map_err(LuaError::external)?;

    let max_connections =
        effective_max_connections(&url, opts.get::<Option<u32>>("max_connections")?);

    let pool = RT
        .block_on(
            AnyPoolOptions::new()
                .max_connections(max_connections)
                .connect(&url),
        )
        .map_err(LuaError::external)?;

    Ok(Connection { pool })
}

fn rows_to_lua(lua: &Lua, rows: Vec<sqlx::any::AnyRow>) -> LuaResult<LuaTable> {
    let out = lua.create_table_with_capacity(rows.len(), 0)?;
    for (i, row) in rows.iter().enumerate() {
        out.raw_set(i + 1, row_to_lua(lua, row)?)?;
    }
    Ok(out)
}

impl LuaUserData for Connection {
    fn add_methods<M: LuaUserDataMethods<Self>>(methods: &mut M) {
        methods.add_method(
            "query",
            |lua, this, (sql, params): (String, Option<LuaTable>)| {
                let mut query = sqlx::query(&sql);
                if let Some(params) = &params {
                    query = bind_params(query, params)?;
                }
                let rows = RT
                    .block_on(query.fetch_all(&this.pool))
                    .map_err(LuaError::external)?;
                rows_to_lua(lua, rows)
            },
        );

        methods.add_method(
            "execute",
            |_, this, (sql, params): (String, Option<LuaTable>)| {
                let mut query = sqlx::query(&sql);
                if let Some(params) = &params {
                    query = bind_params(query, params)?;
                }
                let result = RT
                    .block_on(query.execute(&this.pool))
                    .map_err(LuaError::external)?;
                Ok(result.rows_affected() as i64)
            },
        );

        methods.add_method("transaction", |lua, this, callback: LuaFunction| {
            let mut conn = RT.block_on(this.pool.acquire()).map_err(LuaError::external)?;
            RT.block_on(sqlx::query("BEGIN").execute(&mut *conn))
                .map_err(LuaError::external)?;

            let tx = lua.create_userdata(Transaction {
                conn: RefCell::new(Some(conn)),
            })?;

            let result = callback.call::<()>(&tx);

            let conn = tx.borrow_mut::<Transaction>()?.conn.borrow_mut().take();
            let Some(mut conn) = conn else {
                return Err(LuaError::external("transaction connection lost"));
            };

            // The connection must also be dropped inside the runtime:
            // returning it to the pool spawns a tokio task.
            match result {
                Ok(()) => RT
                    .block_on(async move {
                        sqlx::query("COMMIT").execute(&mut *conn).await?;
                        drop(conn);
                        Ok::<(), sqlx::Error>(())
                    })
                    .map_err(LuaError::external),
                Err(err) => {
                    RT.block_on(async move {
                        let _ = sqlx::query("ROLLBACK").execute(&mut *conn).await;
                        drop(conn);
                    });
                    Err(err)
                }
            }
        });

        methods.add_method("close", |_, this, ()| {
            RT.block_on(this.pool.close());
            Ok(())
        });
    }
}

impl Transaction {
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

