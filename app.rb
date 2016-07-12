require 'bundler'
Bundler.require

use Rack::MethodOverride

# load the Database and models
require './models/model'

Warden::Strategies.add(:password) do
  def valid?
    params['user'] && params['user']['username'] && params['user']['password']
  end

  def authenticate!
    user = User.first(username: params['user']['username'])

    if user.nil?
      throw(:warden, message: "The username you entered does not exist.")
    elsif user.authenticate(params['user']['password'])
      success!(user)
    else
      throw(:warden, message: "The username and password combination ")
    end
  end
end

class SinatraWarden < Sinatra::Base
	enable :sessions
	register Sinatra::Flash
	set :session_secret, 'super_secret' # try [env] variable

	use Warden::Manager do |config|
    # Tell Warden how to save our User info into a session.
    # Sessions can only take strings, not Ruby code, we'll store
    # the User's `id`
    config.serialize_into_session{|user| user.id }
    # Now tell Warden how to take what we've stored in the session
    # and get a User from that information.
    config.serialize_from_session{|id| User.get(id) }

    config.scope_defaults :default,
      # "strategies" is an array of named methods with which to
      # attempt authentication. We have to define this later.
      strategies: [:password],
      # The action is a route to send the user to when
      # warden.authenticate! returns a false answer. We'll show
      # this route below.
      action: 'auth/unauthenticated'
    # When a user tries to log in and cannot, this specifies the
    # app to send the user to.
    config.failure_app = self
  end

  Warden::Manager.before_failure do |env,opts|
    # Because authentication failure can happen on any request but
    # we handle it only under "post '/auth/unauthenticated'", we need
    # to change request to POST
    env['REQUEST_METHOD'] = 'POST'
    # And we need to do the following to work with  Rack::MethodOverride
    env.each do |key, value|
      env[key]['_method'] = 'post' if key == 'rack.request.form_hash'
    end
  end

  helpers do
    def current_user
      @current_user ||= env['warden'].user
    end

    def logged_in?
      current_user ? true : false
    end

    def username
      current_user.username
    end
  end

  # Routes
  get '/' do
    erb :index
  end

  # Sign up
  get '/users/new' do
    current_user = env['warden'].user
    if current_user == nil
      @groups = Group.all(:id.not => 1) # don't allow access to 'admin' group
      erb :'users/new'
    else
      redirect '/protected'
    end
  end

  post '/users/new' do
    username = params['user']['username']
    p = params['user']['password']
    confirm = params['confirm_user']['password']
    user = User.first(username: username)
    if !user.nil?
      flash[:error] = "username already exists, try another"
      redirect '/users/new'
    elsif p != confirm
      flash[:error] = "passwords don't match"
      redirect '/users/new'
    else
      u = User.new
      u.username = username
      u.password = p
      u.time_zone = params[:time_zone].to_i
      u.name = params[:first_last]
      u.group_id = params[:group]
      u.save
    end
    redirect '/auth/login'
  end

  # Log in
  get '/auth/login' do
    erb :'auth/login'
  end

  post '/auth/login' do
    env['warden'].authenticate!

    flash[:success] = "Successfully logged in"

    if session[:return_to].nil?
      redirect '/users/profile'
    else
      redirect session[:return_to]
    end
  end

  # Log out
  get '/auth/logout' do
    env['warden'].raw_session.inspect
    env['warden'].logout
    flash[:success] = 'Successfully logged out'
    redirect '/'
  end

  post '/auth/unauthenticated' do
    session[:return_to] = env['warden.options'][:attempted_path] if session[:return_to].nil?

    # Set the error and use a fallback if the message is not defined
    flash[:error] = env['warden.options'][:message] || "You must log in"
    redirect '/auth/login'
  end

  # Protected route
  get '/protected' do
    user = env['warden']
    user.authenticate!

    redirect "/users/profile"
  end

  # Groups
  get '/groups' do
    # list of all groups, don't need auth
  end

  get '/groups/new' do
    # return html form for creating new group
    # should have list of all assignments
    # and form for new assignments
  end

  post '/groups' do
    # create a new group
  end

  get '/groups/profile' do
    # display link to users and assignments in a group
    @group = Group.get(current_user.group_id)
    @assignments = Assignment.get(:group_id => @group_id)
    # if logged_in?
    #   @group = Group.get(current_user)
    erb :'groups/show'
    # else
    #   flash[:error] = "You must log in"
    #   redirect '/auth/login'
    # end
  end

  get '/groups/:group_id/users' do
    # display other users in group
  end


  # Users
  get "/users/profile" do
    # List links to all users' assignments

    # display link to edit user info

    @group_id = current_user.group_id
    @assignments = Assignment.get(:group_id => @group_id)
    erb :'users/show'
  end

  put '/users/:id/edit' do
    # edit user's name, password, group
    # link to delete user
    erb :'users/edit'
  end

  # Assignments
  get '/groups/:group_id/assignments' do
    erb :'assignments/index'
  end


end
