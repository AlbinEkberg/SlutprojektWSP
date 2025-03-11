require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
require 'bcrypt'
require 'sinatra/flash'

enable :sessions

def connect_to_db()
    db = SQLite3::Database.new('db/clash.db')
    db.results_as_hash = true
    return db
end

def generate_chest()
    db = connect_to_db()
    chests = db.execute("SELECT * FROM chests")
    total_rarity = chests.sum { |chest| chest["rarity"] }
    random_value = rand(total_rarity)

    cumulative_rarity = 0
    p random_value
    selected_chest = chests.find do |chest|
        cumulative_rarity += chest["rarity"]
        random_value < cumulative_rarity
    end

    session[:current_chest] = selected_chest
end

def generate_card()
    db = connect_to_db()
    cards = db.execute("SELECT * FROM cards")
    total_rarity = cards.sum { |card| card["rarity"] }
    random_value = rand(total_rarity)

    cumulative_rarity = 0
    p random_value
    selected_card = cards.find do |card|
        cumulative_rarity += card["rarity"]
        random_value < cumulative_rarity
    end

    session[:current_card] = selected_card
end

# before do
#     if (session[:user_id] == nil) && (request.path_info != '/') && (request.path_info != '/error')
#         session[:error] = "You need to log in to see this"
#         redirect('/error')
#     end
# end

get('/') do
    if session[:current_chest] == nil
        generate_chest()
    end
    slim(:index)
end

# kista antingen välja att spara eller öppna --> öppna --> man får kort + ny kista genereras --> loopa
# kistor slumpas med olika sannolikhet, samma med korten

get('/showlogin') do
    slim(:'users/login')
end

get('/users/register') do
    slim(:'users/register')
end

get('/collection/card') do
    slim(:'collection/card')
end

get('/chest') do
    slim(:'collection/chest')
end

get('/market/index') do
    slim(:'market/index')
end

get('/chest/open') do
    case session[:current_chest]["rarity"]
    when 1..100
        card_amount = 4
    when 101..200
        card_amount = 3
    when 201..300
        card_amount = 2
    end

    while card_amount > 0
        generate_card()
        card_amount -= 1
    end
    slim(:'users/chest_unlock', layout: false)
end

post('/users/login') do
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
    flash[:error] = "Fel lösen"
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

