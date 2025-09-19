class Api::V1::PrCodesController < ApplicationController
  before_action :set_pr_code, only: [:show, :destroy]
  before_action :set_school, only: [:create]

  # GET /api/v1/pr_codes
  def index
    # Assuming you have a way to identify the current school
    pr_codes = PrCodeServices::ListService.call(@school)
    render json: pr_codes
  end

  # GET /api/v1/pr_codes/:code
  def show
    if @pr_code
      render json: @pr_code
    else
      render json: { error: 'PR Code not found' }, status: :not_found
    end
  end

  # POST /api/v1/pr_codes
  def create
    result = PrCodeServices::CreateService.call(pr_code_params, @school)
    if result.success?
      render json: result.pr_code, status: :created
    else
      render json: { errors: result.errors }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/pr_codes/:code
  def destroy
    if @pr_code
      result = PrCodeServices::DestroyService.call(@pr_code)
      if result.success?
        head :no_content
      else
        render json: { errors: result.errors }, status: :unprocessable_entity
      end
    else
      render json: { error: 'PR Code not found' }, status: :not_found
    end
  end

  private

  def set_pr_code
    @pr_code = PrCodeServices::ShowService.call(params[:code])
  end

  # This method has been updated to permit the correct parameters
  def pr_code_params
    params.require(:pr_code).permit(:school_id, :template_id, :channel, :recipient_type, :invite_id)
  end

  # Mock set_school for demonstration
  def set_school
    # In a real app, you would identify the school from the user session,
    # a subdomain, or a request parameter.
    @school = School.find(pr_code_params[:school_id])
    render json: { error: 'School not found' }, status: :not_found unless @school
  end
end
