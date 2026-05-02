const path = require('path');
const fs = require('fs');

let BetterSqlite3 = null;
try {
  BetterSqlite3 = require('better-sqlite3');
} catch (_) {
  BetterSqlite3 = null;
}

let db = null;

function normalizeRunResult(result) {
  if (!result || typeof result !== 'object') return result;
  const out = { ...result };
  if (typeof out.lastInsertRowid === 'bigint' && out.lastInsertRowid <= BigInt(Number.MAX_SAFE_INTEGER)) {
    out.lastInsertRowid = Number(out.lastInsertRowid);
  }
  return out;
}

function createNodeSqliteCompat(dbPath) {
  let DatabaseSync = null;
  try {
    ({ DatabaseSync } = require('node:sqlite'));
  } catch (err) {
    throw new Error(
      '当前 Node 环境无法加载 better-sqlite3，且不支持 node:sqlite。请切换到 Node 22+ 或修复 better-sqlite3 原生模块。'
    );
  }

  const nativeDb = new DatabaseSync(dbPath);

  const compatDb = {
    prepare(sql) {
      const stmt = nativeDb.prepare(sql);
      return {
        run(...params) {
          return normalizeRunResult(stmt.run(...params));
        },
        get(...params) {
          return stmt.get(...params);
        },
        all(...params) {
          return stmt.all(...params);
        },
        iterate(...params) {
          return stmt.iterate(...params);
        },
      };
    },
    exec(sql) {
      return nativeDb.exec(sql);
    },
    pragma(sql) {
      return nativeDb.prepare(`PRAGMA ${sql}`).all();
    },
    transaction(fn) {
      return (...args) => {
        nativeDb.exec('BEGIN');
        try {
          const result = fn(...args);
          nativeDb.exec('COMMIT');
          return result;
        } catch (err) {
          try {
            nativeDb.exec('ROLLBACK');
          } catch (_) {
            // ignore rollback secondary error
          }
          throw err;
        }
      };
    },
    close() {
      nativeDb.close();
    },
  };

  return compatDb;
}

function createDatabase(dbPath, config) {
  if (BetterSqlite3) {
    try {
      return new BetterSqlite3(dbPath, {
        verbose: config.type === 'sqlite' && process.env.DEBUG ? console.log : undefined,
      });
    } catch (err) {
      console.warn('[db] better-sqlite3 初始化失败，自动切换到 node:sqlite 兼容模式:', err.message);
      return createNodeSqliteCompat(dbPath);
    }
  }
  return createNodeSqliteCompat(dbPath);
}

function getDb(config) {
  if (db) return db;
  const dbPath = config.path;
  const dir = path.dirname(dbPath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  db = createDatabase(dbPath, config);
  db.pragma('journal_mode = WAL');
  db.pragma('busy_timeout = 5000');
  return db;
}

function closeDb() {
  if (db) {
    db.close();
    db = null;
  }
}

module.exports = { getDb, closeDb };
