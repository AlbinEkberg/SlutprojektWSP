##
# The Model module contains all database-related methods used in the app,
# such as user authentication, card generation, and data manipulation.
#
# It serves as a separation of concerns from the main Sinatra routes,
# keeping database logic modular and reusable.
module Model

    ##
    # Connects to the SQLite database.
    #
    # @return [SQLite3::Database] the database connection
    def connect_to_db
      db = SQLite3::Database.new('db/clash.db')
      db.results_as_hash = true
      return db
    end
  
    ##
    # Selects a user by username.
    #
    # @param [String] username the username to look up
    # @return [Array<Hash>] array of user records matching the username
    def select_user(username)
      db = connect_to_db
      db.execute("SELECT * FROM users WHERE username = ?", username)
    end
  
    ##
    # Adds a card to a user or adds to balance if the card is gold (ID 44).
    #
    # @param [Array<Hash>] gotten_cards the array of gotten cards, last element is used
    # @param [Integer] id the user's ID
    # @return [void]
    def add_card_to_user(gotten_cards, id)
      db = connect_to_db
      card = gotten_cards[-1][:card]
      amount = gotten_cards[-1][:amount]
  
      if card["id"] != 44
        existing_cards = db.execute("SELECT card_id FROM users_cards_rel WHERE user_id = ?", id)
        if existing_cards.include?({ "card_id" => card["id"] })
          db.execute("UPDATE users_cards_rel SET amount = amount + ? WHERE user_id = ? AND card_id = ?",
                     [amount, id, card["id"]])
        else
          db.execute("INSERT INTO users_cards_rel (user_id, card_id, amount, level, for_sale) VALUES (?,?,?,?,?)",
                     [id, card["id"], amount, card["base_lvl"], 0])
        end
      else
        db.execute("UPDATE users SET balance = balance + ? WHERE id = ?", [amount, id])
      end
    end
  
    ##
    # Reloads and returns the current balance for a user.
    #
    # @param [Integer] id the user's ID
    # @return [Integer, nil] the balance or nil if user not found
    def reload_balance(id)
      db = connect_to_db
      db.execute("SELECT balance FROM users WHERE id = ?", id).first["balance"] if id
    end
  
    ##
    # Selects all users from the database.
    #
    # @return [Array<Hash>] all user records
    def select_all_users
      db = connect_to_db
      db.execute("SELECT * FROM users")
    end
  
    ##
    # Selects all cards excluding the gold card (ID 44).
    #
    # @return [Array<Hash>] card records
    def select_all_cards
      db = connect_to_db
      db.execute("SELECT * FROM cards WHERE id != ?", 44)
    end
  
    ##
    # Selects all user-card relationships for a user, excluding gold.
    #
    # @param [Integer] id the user's ID
    # @return [Array<Hash>] cards belonging to the user
    def select_all_users_cards(id)
      db = connect_to_db
      db.execute("SELECT * FROM users_cards_rel WHERE user_id = ? AND card_id != ?", [id, 44])
    end
  
    ##
    # Creates a new user if passwords match and returns the new user.
    #
    # @param [String] username the desired username
    # @param [String] password the password
    # @param [String] password_confirm the confirmation password
    # @return [Hash, nil] the new user record or nil on mismatch
    def password_digest(username, password, password_confirm)
      db = connect_to_db
      if password == password_confirm
        digest = BCrypt::Password.create(password)
        db.execute("INSERT INTO users (username, pwdigest, balance) VALUES (?,?,?)", [username, digest, 1000])
  
        db = connect_to_db # reconnect to fetch the new user
        db.execute("SELECT * FROM users WHERE username = ?", username).first
      else
        session[:register_error_message] = "Passwords do not match"
        redirect('/users/register')
      end
    end
  
    ##
    # Deletes a user by ID.
    #
    # @param [Integer] id the user's ID
    # @return [void]
    def delete_user(id)
      db = connect_to_db
      db.execute("DELETE FROM users WHERE id = ?", id)
    end
  
    ##
    # Checks if the current session user is an admin.
    # Redirects to login if not an admin.
    #
    # @return [void]
    def check_admin
      db = connect_to_db
      admins = db.execute("SELECT id FROM users WHERE admin IS NOT NULL")
      unless admins.any? { |admin| admin["id"] == session[:id] }
        redirect('/showlogin')
      end
    end
  
    ##
    # Generates a chest for the session based on rarity weights.
    #
    # @return [void]
    def generate_chest
      db = connect_to_db
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
  
    ##
    # Generates a card based on the current chest rarity and weighted randomness.
    #
    # @return [Hash] card data and amount => { card: Hash, amount: Integer }
    def generate_card
      db = connect_to_db
      reverse_chest_rarity = 1 + (50 / session[:current_chest]["rarity"])
  
      selection = rand(1..(100 - reverse_chest_rarity))
  
      case selection
      when 1
        rarity = "legendary"
        amount = 1
      when 2..12
        rarity = "epic"
        amount = rand(1..5) + (reverse_chest_rarity / 2).to_i
      when 13..33
        rarity = "rare"
        amount = rand(5..20) + reverse_chest_rarity
      when 34..70
        rarity = "common"
        amount = rand(20..100) + (reverse_chest_rarity * 2)
      else
        rarity = "gold"
        amount = rand(100..1000) * reverse_chest_rarity
      end
  
      cards_of_rarity = db.execute("SELECT * FROM cards WHERE rarity = ?", rarity)
      selected_card = cards_of_rarity.sample
  
      { card: selected_card, amount: amount }
    end
  end
  