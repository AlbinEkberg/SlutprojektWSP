# frozen_string_literal: true

require 'sinatra'
require 'slim'
require 'sqlite3'
require 'sinatra/reloader'
require 'bcrypt'
require 'sinatra/flash'
require_relative './model/model.rb'

enable :sessions

include Model

before do
  protected_routes = ["/card", "/market"]

  if protected_routes.include?(request.path_info) && session[:id].nil?
    flash[:need_login] = "You need to log in to see this"
    redirect('/showlogin')
  end
end

##
# GET /
#
# Displays the homepage. If no chest exists in the session, one is generated.
#
# @return [Slim::Template] Renders the index view.
get('/') do
  generate_chest() if session[:current_chest].nil?
  slim(:index)
end

##
# GET /showlogin
#
# Displays the login page.
#
# @return [Slim::Template] Renders the login form.
get('/showlogin') do
  slim(:'users/login')
end

##
# GET /users/register
#
# Displays the user registration form.
#
# @return [Slim::Template] Renders the user registration form.
get('/users/register') do
  slim(:'users/new')
end

##
# GET /card
#
# Displays all cards and the current user's card collection.
#
# @return [Slim::Template] Renders the cards overview.
get('/card') do
  cards = select_all_cards()
  cards_rel = select_all_users_cards(session[:id])
  slim(:'card/index', locals: { cards: cards, cards_rel: cards_rel })
end

##
# GET /users/logout
#
# Logs the user out, destroys the session, and redirects to the homepage.
#
# @return [Redirect] Redirects to homepage.
get('/users/logout') do
  session.destroy
  flash[:logout] = "You have been logged out"
  redirect('/')
end

##
# GET /market
#
# Displays the market page.
#
# @return [Slim::Template] Renders the market view.
get('/market') do
  slim(:'market/index')
end

##
# GET /card/show
#
# Displays a single card. Used when opening a chest.
#
# @return [Slim::Template] Renders card show view without layout.
get('/card/show') do
  slim(:'card/show', layout: false)
end

##
# GET /admin
#
# Displays the admin panel if the user is an admin.
#
# @return [Slim::Template] Renders the admin dashboard.
get('/admin') do
  check_admin()
  users = select_all_users()
  slim(:'admin/index', layout: false, locals: { users: users })
end

##
# POST /admin/:id/delete
#
# Deletes a user with the given ID. Only accessible by admin.
#
# @param [Integer] id The ID of the user to delete.
# @return [Redirect] Redirects back to the admin panel.
post('/admin/:id/delete') do
  check_admin()
  delete_user(params[:id].to_i)
  redirect('/admin')
end

##
# POST /chest/open
#
# Opens a chest, generates cards, and stores them in the session.
# Redirects to card reveal or homepage.
#
# @return [Redirect] Redirects to card reveal or homepage depending on chest status.
post('/chest/open') do
  if session[:current_chest]
    case session[:current_chest]["rarity"]
    when 1..9
      card_amount = 4
    when 10..99
      card_amount = 3
    else
      card_amount = 2
    end

    gotten_cards = []
    db = connect_to_db()
    card_amount.times do
      card = generate_card()
      gotten_cards << card
      add_card_to_user([card], session[:id]) if session[:id]
    end

    session[:current_chest] = nil
    session[:cards_left] = gotten_cards.length
    session[:gotten_cards] = gotten_cards
    session[:balance] = reload_balance(session[:id])
  end

  if session[:cards_left].to_i > 0
    session[:current_card] = session[:gotten_cards][session[:cards_left] - 1]
    session[:cards_left] -= 1
    redirect('/card/show')
  else
    redirect('/')
  end
end

##
# POST /users/login
#
# Handles user login.
#
# @param [String] username
# @param [String] password
# @return [Redirect] Redirects to home or admin depending on user type, or back to login on failure.
post('/users/login') do
  username = params[:username]
  password = params[:password]

  if username.empty? || password.empty?
    session[:login_error_message] = "You need to fill in all fields"
    redirect('/showlogin')
  end

  result = select_user(username).first

  if result.nil?
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
    redirect(result["admin"] ? '/admin' : '/')
  else
    session[:login_error_message] = "Wrong password"
    redirect('/showlogin')
  end
end

##
# POST /users/new
#
# Handles new user registration.
#
# @param [String] username
# @param [String] password
# @param [String] password_confirm
# @return [Redirect] Redirects to home or back to registration with error.
post('/users/new') do
  username = params[:username]
  password = params[:password]
  password_confirm = params[:password_confirm]

  if username.empty? || password.empty? || password_confirm.empty?
    session[:register_error_message] = "You need to fill in all fields"
    redirect('/users/register')
  end

  if select_user(username).any?
    session[:register_error_message] = "Username already taken"
    redirect('/users/register')
  end

  result = password_digest(username, password, password_confirm)

  if result
    session[:id] = result["id"]
    session[:balance] = result["balance"]
    session[:username] = username
    flash[:login] = "Successfully logged in as #{username}"
    redirect('/')
  end
end