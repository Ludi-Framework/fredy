//! Connection options: adapter → connection URL and pool sizing.

pub fn build_url(
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
pub fn effective_max_connections(url: &str, requested: Option<u32>) -> u32 {
    if url == "sqlite::memory:" {
        1
    } else {
        requested.unwrap_or(5)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn build_url_postgres_passthrough() {
        let url = build_url("postgres", Some("postgres://u:p@h/db".into()), None).unwrap();
        assert_eq!(url, "postgres://u:p@h/db");
    }

    #[test]
    fn build_url_postgres_requires_url() {
        assert!(build_url("postgres", None, None).is_err());
    }

    #[test]
    fn build_url_sqlite_memory() {
        let url = build_url("sqlite", None, Some(":memory:".into())).unwrap();
        assert_eq!(url, "sqlite::memory:");
    }

    #[test]
    fn build_url_sqlite_file() {
        let url = build_url("sqlite", None, Some("data.db".into())).unwrap();
        assert_eq!(url, "sqlite://data.db?mode=rwc");
    }

    #[test]
    fn build_url_sqlite_requires_path() {
        assert!(build_url("sqlite", None, None).is_err());
    }

    #[test]
    fn build_url_unknown_adapter() {
        let err = build_url("mongo", None, None).unwrap_err();
        assert!(err.contains("unknown adapter 'mongo'"));
    }

    #[test]
    fn memory_sqlite_forces_single_connection() {
        assert_eq!(effective_max_connections("sqlite::memory:", Some(10)), 1);
        assert_eq!(effective_max_connections("sqlite::memory:", None), 1);
    }

    #[test]
    fn max_connections_defaults_to_five() {
        assert_eq!(effective_max_connections("postgres://h/db", None), 5);
        assert_eq!(effective_max_connections("postgres://h/db", Some(20)), 20);
    }
}
