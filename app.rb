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

def generate_chest() # väljer en kista baserat på sällsynthet högre sällsynthet = bättre kista
    db = connect_to_db()
    chests = db.execute("SELECT * FROM chests")
    total_rarity = chests.sum { |chest| chest["rarity"] }
    random_value = rand(total_rarity)

    cumulative_rarity = 0
    selected_chest = chests.find do |chest|
        cumulative_rarity += chest["rarity"]
        random_value < cumulative_rarity
    end

    session[:current_chest] = selected_chest
end

def generate_card() # väljer ett kort baserat på sällsynthet högre sällsynthet = bättre kort
    db = connect_to_db()
    cards = db.execute("SELECT * FROM cards")
    total_rarity = cards.sum { |card| card["rarity"] }
    random_value = rand(total_rarity)

    cumulative_rarity = 0
    selected_card = cards.find do |card|
        cumulative_rarity += card["rarity"]
        random_value < cumulative_rarity
    end

    return selected_card
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

get('/showlogin') do
    slim(:'users/login')
end

get('/users/register') do
    slim(:'users/register')
end

get('/collection/card') do
    db = connect_to_db()
    cards = db.execute("SELECT * FROM cards")
    cards_rel = db.execute("SELECT * FROM users_cards_rel WHERE user_id = ?",session[:id])
    slim(:'collection/card',locals:{cards:cards,cards_rel:cards_rel})
end

get('/albums') do

end

get('/chest') do
    slim(:'collection/chest')
end

get('/market/index') do
    slim(:'market/index')
end

get('/showchest') do
    slim(:'users/chest_unlock', layout: false)
end

post('/chest/open') do
    if session[:current_chest] != nil # körs första gången
        case session[:current_chest]["rarity"] # olika mängd kort beroende på sällsynthet
        when 1..100
            card_amount = 4
        when 101..200
            card_amount = 3
        when 201..300
            card_amount = 2
        end

        gotten_cards = []
        db = connect_to_db()
        i = card_amount
        while i > 0
            gotten_cards << generate_card()
            if db.execute("SELECT card_id FROM users_cards_rel WHERE user_id = ?",session[:id]).include?({ "card_id" => gotten_cards[-1]['id'] })
                db.execute("UPDATE users_cards_rel SET amount = amount + 1 WHERE user_id = ? AND card_id = ?",[session[:id],gotten_cards[-1]["id"]])
            else
                db.execute("INSERT INTO users_cards_rel (user_id, card_id, amount, level, for_sale) VALUES (?,?,?,?,?)",[session[:id],gotten_cards[-1]["id"],1,gotten_cards[-1]["base_lvl"],0])
            end
            i -= 1
        end
        

        session[:current_chest] = nil
        session[:cards_left] = card_amount
        session[:gotten_cards] = gotten_cards
    end

    if session[:cards_left] > 0 # körs varje gång du klickar för att vissa nästa kort
        session[:current_card] = session[:gotten_cards][session[:cards_left] - 1]
        session[:cards_left] -= 1
        redirect('/showchest')
    else
        redirect('/')
    end
end

post('/users/login') do
    username = params[:username]
    password = params[:password]
    db = connect_to_db()
    result = db.execute("SELECT * FROM users WHERE username = ?",username).first
    if result == nil
        flash[:error] = "No such user"
    end
    pwdigest = result["pwdigest"]
    id = result["id"]

    if BCrypt::Password.new(pwdigest) == password
        session[:id] = id
        session[:username] = username
        redirect('/')
    else
        flash[:error] = "Wrong password"
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

