def connect_to_db()
    db = SQLite3::Database.new('db/clash.db')
    db.results_as_hash = true
    return db
end