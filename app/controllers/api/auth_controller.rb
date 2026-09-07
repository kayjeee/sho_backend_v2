# app/controllers/api/auth_controller.rb
module Api
  class AuthController < ApplicationController
    def login
      render json: { success: true, message: "Intercepted by Rails Auth Handler" }, status: :ok
    end

    def me
      render json: { success: true, message: "Intercepted by Rails Session Handler" }, status: :ok
    end
  end
end
