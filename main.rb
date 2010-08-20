require 'erb'
require 'securerandom'
require 'yaml/store'
require 'rubygems'
require 'json'
require 'oauth'
require 'haml'
require 'sinatra'


helpers do
  include Rack::Utils
  alias_method :h, :escape_html

  def oauth_consumer
    OAuth::Consumer.new(KEY, SECRET, :site => 'http://api.twitter.com')
  end

  def base_url
    default_port = (request.scheme == "http") ? 80 : 443
    port = (request.port == default_port) ? "" : ":#{request.port.to_s}"
    "#{request.scheme}://#{request.host}#{port}"
  end

  def get_screen_name(access_token)
    JSON.parse(
      access_token.get(
        "http://api.twitter.com/1/account/verify_credentials.json").body)['screen_name']
  end

  def get_access_token(key, secret)
    OAuth::AccessToken.new(oauth_consumer, key, secret)
  end
end

configure do
  #use Rack::Session::Cookie, :secret => SecureRandom.hex(32)
  KEY = "LSqBgPWzKdoRhgqyy8FSwA"
  SECRET = "B8IVWN4iLuIhiYvJNNFY5gHlH5BNHohIlfAI9R9zw"
  $db = YAML::Store.new('data.yaml')
  enable :sessions
  set :public, File.dirname(__FILE__) + '/public'
  set :views, File.dirname(__FILE__) + '/views'
end

before do
  if session[:access_token]
    @access_token = get_access_token(session[:access_token], session[:access_token_secret])
  else
    @access_token = nil
  end
end

get '/stylesheet.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass :stylesheet
end

get '/' do
  haml :index
end

get '/make_clan' do
  redirect '/clan/' + params[:clan_name]
end

get '/clan/:clan_name' do |clan_name|
  @clan_name = clan_name
  session[:clan_name] = @clan_name
  $db.transaction do
    $db[@clan_name] = {} if $db[@clan_name] == nil
    haml :clan
  end
end


get '/request_token' do
  callback_url = "#{base_url}/access_token"
  request_token = oauth_consumer.get_request_token(:oauth_callback => callback_url)
  session[:request_token] = request_token.token
  session[:request_token_secret] = request_token.secret
  redirect request_token.authorize_url
end

get '/access_token' do
  request_token = OAuth::RequestToken.new(
    oauth_consumer, session[:request_token], session[:request_token_secret])
  begin
    @access_token = request_token.get_access_token(
      {},
      :oauth_token => params[:oauth_token],
      :oauth_verifier => params[:oauth_verifier])
  rescue OAuth::Unauthorized => @exception
    return erb %{oauth failed: <%=h @exception.message %>}
  end
  session[:access_token] = @access_token.token
  session[:access_token_secret] = @access_token.secret
  @screen_name = get_screen_name(@access_token)
  $db.transaction do
    $db[session[:clan_name]][@screen_name] = {
      :token => @access_token.token,
      :secret => @access_token.secret,
      :screen_name => @screen_name}
  end
  haml %(
ログイン / クランへの参加に成功しました！
%a{:href => "/tweet"}
  ツイートする
  )
end

get '/tweet' do
  haml :tweet
end

post '/do_tweet' do
  def result_message(response)
    case response
    when Net::HTTPSuccess
      "成功"
    else
      "失敗:" + response.code.to_s
    end
  end

  @output = []
  if params[:tweet_type] == 'reply'
    $db.transaction do
      $db[session[:clan_name]].each_value do |user|
        token = get_access_token(user[:token], user[:secret])
        response = token.post('http://api.twitter.com/1/statuses/update.json',
                               'status' => "@#{user[:screen_name]} #{params[:tweet]}")
        @output.push({:type => :to_reply, 
          :user => user[:screen_name], :result => result_message(response)})
      end
    end
  else
    response = @access_token.post('http://api.twitter.com/1/statuses/update.json',
                                'status' => params[:tweet])
    @output.push({:type => :tweet, :result => result_message(response)})
    status_id = JSON.parse(response.body)['id']
    $db.transaction do
      $db[session[:clan_name]].each_value do |user|
        token = get_access_token(user[:token], user[:secret])
        response = token.post("http://api.twitter.com/1/statuses/retweet/#{status_id}.json")
        @output.push({:type => :rt, 
          :user => user[:screen_name], :result => result_message(response)})

        response = token.post("http://api.twitter.com/1/favorites/create/#{status_id}.json")
        @output.push({:type => :fav, 
          :user => user[:screen_name], :result => result_message(response)})
      end
    end
  end

  haml :do_tweet, :layout => false 
end
