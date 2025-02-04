require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
require 'bcrypt'

enable :sessions

# before do
#     if (session[:user_id] == nil) && (request.path_info != '/') && (request.path_info != '/error')
#         session[:error] = "You need to log in to see this"
#         redirect('/error')
#     end
# end
def connect_to_db()
    db = SQLite3::Database.new('db/clash.db')
    db.results_as_hash = true
    return db
end

get('/') do
    slim(:index)
end

# kista antingen välja att spara eller öppna --> öppna --> man får kort + ny kista genereras --> loopa
# kistor slumpas med olika sannolikhet, samma med korten

get('/showlogin') do
    slim(:login)
end

get('/showregister') do
    slim(:register)
end

get('/cardcollection') do
    slim(:card_collection)
end

get('/chestcollection') do
    slim(:chestcollection)
end

get('/market') do
    slim(:market)
end

post('/login') do
    username = params[:username]
    password = params[:password]
    db = connect_to_db()
    result = db.execute("SELECT * FROM users WHERE username = ?",username).first
    pwdigest = result["pwdigest"]
    id = result["id"]

  if BCrypt::Password.new(pwdigest) == password
    session[:username] = username
    redirect('/')
  else
    "Fel lösen"
  end
end

post('/users/new') do
    username = params[:username]
    password = params[:password]
    password_confirm = params[:password_confirm]
  
    if (password == password_confirm)
        password_digest = BCrypt::Password.create(password)
        db = SQLite3::Database.new('db/clash.db')
        db.execute("INSERT INTO users (username, pwdigest, balance) VALUES (?,?,?)",[username,password_digest,1000])
        redirect('/')
    else
        "password mismatch"
    end
  end