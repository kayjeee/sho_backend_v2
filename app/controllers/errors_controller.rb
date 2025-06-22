class ErrorsController < ApplicationController
  def route_not_found
    render json: { 
      success: false, 
      error: "Endpoint not found" 
    }, status: :not_found
  end
end