require "sinatra"
require "sinatra/namespace"
require "warden"
require "json"


class App < Sinatra::Base
  register Sinatra::Namespace

  set :bind, "0.0.0.0"
  set :port, 9494
  
  configure :production do
    puts "mode prod"
    set :mode, "prod"
  end
  configure :test do
    puts "mode test"
    set :mode, "test"
  end

  enable :sessions

  Warden::Manager.serialize_from_session do |id|
    User.get(id)
  end
  Warden::Manager.serialize_into_session do |user|
    user[:name]
  end

  class LoginTest < Warden::Strategies::Base
    def self.read_accounts
      accounts = {}
      path = if !ENV["ACCOUNT_FILE"].nil?
          ENV["ACCOUNT_FILE"]
        elsif ENV["APP_ENV"] == "production"
          "/data/prod/accounts"
        else
          "/data/test/accounts"
        end
      File.open(path) do |f|
        f.each_line do |line|
          account = line.strip.split ","
          raise ArgumentError, "Invalid account file format" unless account.length == 2
          accounts[account[0]] = account[1]
        end
      end
      accounts
    end

    def self.valid_user?(accounts, user, password)
      accounts[user] == password
    end

    def get_login_info
      if params["name"] && params["password"]
        return params
      end
      request.body.rewind
      body = JSON.parse(request.body.read)
      if body["name"] && body["password"]
        return body
      end
      nil
    rescue JSON::ParserError
      nil
    end

    # 認証に必要なデータが送信されているか検証
    def valid?
      self.get_login_info.nil? ? false : true
    end

    # 認証
    def authenticate!
      info = self.get_login_info

      if LoginTest.valid_user?(LoginTest.read_accounts, info["name"], info["password"])
        # ユーザー名とパスワードが正しければログイン成功
        user = {
          :name => info["name"],
          :password => info["password"],
        }
        success!(user)
      else
        fail!("Could not log in")
      end
    end
  end

  Warden::Strategies.add(:login_test, LoginTest)

  use Warden::Manager do |manager|
    # 先ほど登録したカスタム認証方式をデフォルトにする
    manager.default_strategies :login_test

    # 認証に失敗したとき呼び出す Rack アプリを設定(必須)
    #    manager.failure_app = Sinatra::Application
    manager.failure_app = App
  end

  helpers do
    def warden
      request.env["warden"]
    end

    def login?
      !warden.user.nil?
    end

    def login_user
      warden.user
    end

    def logout
      warden.logout
    end

    def make_response(status_code, message)
      status status_code
      JSON.generate({ message: message })
    end
  end
  namespace "/app_proxy" do

    post "/api/httpd/graceful" do
      return status 403 unless login?
      begin
        ###
      rescue ScriptError => e
        p e.message
        make_response 400, "script error."
      rescue ArgumentError, JSON::ParserError => e
        p e.message
        make_response 400, "invalid parameter. json parse error"
      end
    end

    post "/api/login" do
      warden.logout
      warden.authenticate!
      status 200
    end

    post "/unauthenticated" do
      status 401
    end

    post "/api/logout" do
      logout
        status 200
    end
  end
  not_found do
    "404 Not Found"
  end
end
