package store

import (
	"context"
	"fmt"
)

const schema = `
CREATE TABLE profiles(id TEXT PRIMARY KEY, display_name TEXT NOT NULL, created_at TEXT NOT NULL);
CREATE TABLE sessions(
 id TEXT PRIMARY KEY,
 profile_id TEXT NOT NULL REFERENCES profiles(id),
 client_session_id TEXT NOT NULL,
 performed_at TEXT NOT NULL,
 protocol_version TEXT NOT NULL,
 source TEXT NOT NULL CHECK(source IN ('observed','synthetic')),
 payload TEXT NOT NULL,
 document TEXT NOT NULL,
 UNIQUE(profile_id, client_session_id)
);
CREATE INDEX sessions_history ON sessions(profile_id,performed_at DESC,id DESC);
CREATE INDEX sessions_baseline ON sessions(profile_id,source,protocol_version,performed_at DESC,id DESC);
CREATE TABLE explanations(
 session_id TEXT NOT NULL REFERENCES sessions(id),
 fingerprint TEXT NOT NULL,
 document TEXT NOT NULL,
 PRIMARY KEY(session_id,fingerprint)
);
PRAGMA user_version=1;
`

func (s *Store) migrate(ctx context.Context) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	var version int
	if err = tx.QueryRowContext(ctx, "PRAGMA user_version").Scan(&version); err != nil {
		return err
	}
	if version > 1 {
		return fmt.Errorf("database schema %d is newer than supported version 1", version)
	}
	if version == 0 {
		if _, err = tx.ExecContext(ctx, schema); err != nil {
			return err
		}
	}
	return tx.Commit()
}
