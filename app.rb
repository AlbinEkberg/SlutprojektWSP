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
    reverse_chest_rarity = 1 + (50 / session[:current_chest]["rarity"])

    p reverse_chest_rarity

    selection = rand(1..(100 - reverse_chest_rarity)) # håll på ett tag med det här, inte en bra lösning men fungerar

    case selection
    when 1
        rarity = "legendary"    # 1% baschans
        amount = 1
    when 2..12
        rarity = "epic"         # 10% baschans
        amount = rand(1..5) + (reverse_chest_rarity / 2).to_i
    when 13..33
        rarity = "rare"         # 20% baschans
        amount = rand(5..20) + reverse_chest_rarity
    when 34..70
        rarity = "common"       # 35% baschans
        amount = rand(20..100) + (reverse_chest_rarity * 2)
    else
        rarity = "gold"
        amount = rand(100..1000) * reverse_chest_rarity
    end
    cards_of_rarity = db.execute("SELECT * FROM cards WHERE rarity = ?",rarity)
    selected_card = cards_of_rarity.sample

    return { card: selected_card, amount: amount }
end

before do
    protected_routes = ["/collection/card", "/collection/chest", "/market/index"] # routes som kräver inloggning

    if protected_routes.include?(request.path_info) && session[:id] == nil
        flash[:need_login] = "You need to log in to see this"
        redirect('/showlogin')
    end
end

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
    cards = db.execute("SELECT * FROM cards WHERE id != ?",44)
    cards_rel = db.execute("SELECT * FROM users_cards_rel WHERE user_id = ? AND card_id != ?",[session[:id],44])
    slim(:'collection/card',locals:{cards:cards,cards_rel:cards_rel})
end

get('/users/logout') do
    session.destroy
    flash[:logout] = "You have been logged out"
    redirect('/')
end

get('/collection/chest') do
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
        when 1..9
            card_amount = 4
        when 10..99
            card_amount = 3
        else
            card_amount = 2
        end

        gotten_cards = []
        db = connect_to_db()
        i = card_amount
        while i > 0
            gotten_cards << generate_card()
            if session[:id] != nil
                if gotten_cards[-1][:card]["id"] != 44 # om det är en guldklimp så ska den inte läggas till i databasen
                    if db.execute("SELECT card_id FROM users_cards_rel WHERE user_id = ?",session[:id]).include?({ "card_id" => gotten_cards[-1][:card]["id"] })
                        db.execute("UPDATE users_cards_rel SET amount = amount + ? WHERE user_id = ? AND card_id = ?",[gotten_cards[-1][:amount],session[:id],gotten_cards[-1][:card]["id"]])

                    else
                        db.execute("INSERT INTO users_cards_rel (user_id, card_id, amount, level, for_sale) VALUES (?,?,?,?,?)",[session[:id],gotten_cards[-1][:card]["id"],gotten_cards[-1][:amount],gotten_cards[-1][:card]["base_lvl"],0])
                    end
                else
                    db.execute("UPDATE users SET balance = balance + ? WHERE id = ?",[gotten_cards[-1][:amount], session[:id]])
                end
            end
            i -= 1
        end
        

        session[:current_chest] = nil
        session[:cards_left] = card_amount
        session[:gotten_cards] = gotten_cards
        session[:balance] = db.execute("SELECT balance FROM users WHERE id = ?",session[:id]).first["balance"] if session[:id] != nil
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
    if username == "" || password == ""
        session[:login_error_message] = "You need to fill in all fields"
        redirect('/showlogin')
    end
    db = connect_to_db()
    result = db.execute("SELECT * FROM users WHERE username = ?",username).first

    if result == nil
        session[:login_error_message] = "No such user"
        redirect('/showlogin')
    end

    pwdigest = result["pwdigest"]
    id = result["id"]

    if BCrypt::Password.new(pwdigest) == password
        session[:id] = id
        session[:username] = username
        session[:balance] = result["balance"]
        flash[:login] = "Successfully logged in as #{username}"
        redirect('/')
    else
        session[:login_error_message] = "Wrong password"
        redirect('/showlogin')
    end
end

post('/users/new') do
    username = params[:username]
    password = params[:password]
    password_confirm = params[:password_confirm]
    db = connect_to_db()

    if username == "" || password == "" || password_confirm == ""
        session[:register_error_message] = "You need to fill in all fields"
        redirect('/users/register')
    end

    if db.execute("SELECT * FROM users WHERE username = ?", username).any?
        session[:register_error_message] = "Username already taken"
        redirect('/users/register')
    end

    if (password == password_confirm)
        password_digest = BCrypt::Password.create(password)
        db = SQLite3::Database.new('db/clash.db')
        db.execute("INSERT INTO users (username, pwdigest, balance) VALUES (?,?,?)",[username,password_digest,1000])
        
        db = connect_to_db() # connect again to get the new user

        result = db.execute("SELECT * FROM users WHERE username = ?", username).first

        session[:id] = result["id"]
        session[:balance] = result["balance"]
        session[:username] = username
        flash[:login] = "Successfully logged in as #{username}"
        redirect('/')
    else
        session[:register_error_message] = "Passwords do not match"
        redirect('/users/register')
    end
end

