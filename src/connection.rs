//! Pooled connection userdata: query, execute, transaction, close,
//! plus adapter/pool introspection.

use mlua::prelude::*;
use sqlx::AnyPool;
use sqlx::any::AnyPoolOptions;

use crate::config::{build_url, effective_max_connections};
use crate::runtime::RT;
use crate::transaction::Transaction;
use crate::values::{bind_params, rows_to_lua};

pub struct Connection {
    pool: AnyPool,
    adapter: String,
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

    Ok(Connection { pool, adapter })
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
            let mut conn = RT
                .block_on(this.pool.acquire())
                .map_err(LuaError::external)?;
            RT.block_on(sqlx::query("BEGIN").execute(&mut *conn))
                .map_err(LuaError::external)?;

            let tx = lua.create_userdata(Transaction::new(conn))?;

            let result = callback.call::<()>(&tx);

            let conn = tx.borrow::<Transaction>()?.take();
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

        methods.add_method("adapter", |_, this, ()| Ok(this.adapter.clone()));

        methods.add_method("pool_status", |lua, this, ()| {
            let status = lua.create_table()?;
            status.set("size", this.pool.size())?;
            status.set("idle", this.pool.num_idle())?;
            Ok(status)
        });
    }
}
