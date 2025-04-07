def connect_to_db()
    db = SQLite3::Database.new('db/clash.db')
    db.results_as_hash = true
    return db
end

def check_correct_user()

end

def select_all(where)
    db = connect_to_db()
    result = db.execute("SELECT * FROM #{where}")
    return result
end

def delete(where, id)
    db = connect_to_db()
    db.execute("DELETE FROM #{where} WHERE id = ?", id)
end

def check_admin()
    db = connect_to_db()
    admins = db.execute("SELECT id FROM users WHERE admin IS NOT NULL")
    if admins.any? { |admin| admin["id"] != session[:id] }
        redirect('/showlogin')
    end
end