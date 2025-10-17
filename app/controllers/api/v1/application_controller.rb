# app/controllers/api/v1/application_controller.rb
module Api
  module V1
    class ApplicationController < ::ApplicationController
      # For API-only apps, forgery protection isn’t used
      # You can handle authentication or CSRF tokens manually if needed
    end
  end
end
