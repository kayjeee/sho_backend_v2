# app/controllers/api/v1/application_controller.rb
module Api
  module V1
    class ApplicationController < ::ApplicationController
      protect_from_forgery with: :null_session
    end
  end
end
