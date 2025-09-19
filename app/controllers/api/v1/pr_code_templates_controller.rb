# app/controllers/api/v1/pr_code_templates_controller.rb
class Api::V1::PrCodeTemplatesController < ApplicationController
  # Assuming current_user is available from a parent controller like ApplicationController
  # skip_before_action :authenticate_request, only: [:some_public_action] # Example
  before_action :set_pr_code_template, only: [:show, :update, :destroy]

  # GET /api/v1/pr_code_templates
  def index
    @pr_code_templates = PrCodeTemplateServices::ListTemplatesService.call(current_user)
    render json: @pr_code_templates
  end

  # GET /api/v1/pr_code_templates/:id
  def show
    render json: @pr_code_template
  end

  # POST /api/v1/pr_code_templates
  def create
    result = PrCodeTemplateServices::CreateTemplateService.call(pr_code_template_params, current_user)
    if result.success?
      render json: result.pr_code_template, status: :created
    else
      render json: { errors: result.errors }, status: :unprocessable_entity
    end
  end

  # PATCH/PUT /api/v1/pr_code_templates/:id
  def update
    result = PrCodeTemplateServices::UpdateTemplateService.call(@pr_code_template, pr_code_template_params)
    if result.success?
      render json: result.pr_code_template
    else
      render json: { errors: result.errors }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/pr_code_templates/:id
  def destroy
    result = PrCodeTemplateServices::DestroyTemplateService.call(@pr_code_template)
    if result.success?
      head :no_content
    else
      render json: { errors: result.errors }, status: :unprocessable_entity
    end
  end

  private

  def set_pr_code_template
    # Add authorization check if necessary, e.g., using Pundit
    # authorize @pr_code_template
    @pr_code_template = PrCodeTemplate.find(params[:id])
  end

  def pr_code_template_params
    params.require(:pr_code_template).permit(
      :name, 
      :description, 
      :subject, 
      :content,
      :is_default, # If admins can create default templates
      channels: []
    )
  end

  # This assumes `current_user` is available from a higher-level controller
  # (e.g., ApplicationController) and handles authentication.
end
