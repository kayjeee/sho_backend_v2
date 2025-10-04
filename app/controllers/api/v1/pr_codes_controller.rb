# app/controllers/api/v1/pr_codes_controller.rb
class Api::V1::PrCodesController < ApplicationController
  before_action :set_school
  before_action :authorize_school_access!

  # POST /api/v1/schools/:school_id/pr_codes
  def create
    # Try different service class names - use the one that exists in your app
    service = GeneratePrCodeService.new(
      @school,
      pr_code_params[:purpose],
      nil, # no current_user
      pr_code_params[:metadata] || {}
    )
    
    # OR if it's in a module:
    # service = PrCodeService::Generate.new(...)
    # service = PrCodeGeneratorService.new(...)
    # service = GeneratePrCode.new(...)

    if service.call
      render json: {
        pr_code: PrCodeSerializer.new(service.pr_code).serializable_hash,
        message: "PR code generated successfully"
      }, status: :created
    else
      render json: { errors: service.errors }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/schools/:school_id/pr_codes
  def index
    pr_codes = @school.pr_codes.order(created_at: :desc)
    
    render json: {
      pr_codes: PrCodeSerializer.new(pr_codes).serializable_hash,
      meta: {
        total_count: pr_codes.count,
        school_name: @school.name
      }
    }
  end

  private

  def set_school
    @school = School.find_by(id: params[:school_id])
    return render json: { error: "School not found" }, status: :not_found unless @school
  end

  def authorize_school_access!
    # Add your authorization logic here
    # For now, allow all - implement proper auth as needed
  end

  def pr_code_params
    params.require(:pr_code).permit(
      :purpose, 
      metadata: [
        :school_name, 
        :academic_year, 
        :generated_at, 
        :scope,
        channels: []
      ]
    )
  end
end