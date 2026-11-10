# frozen_string_literal: true

module Api
  module V1
    class CatalogItemsController < Api::V1::BaseController
      skip_before_action :authorize, raise: false
      before_action :resolve_user
      before_action :set_school, only: %i[index create]
      before_action :set_catalog_item, only: %i[show update destroy]
      before_action :require_school_admin, only: %i[create update destroy]

      # GET /api/v1/schools/:school_id/catalog_items
      def index
        items = CatalogItem.by_school(@school.id.to_s)

        # Filters
        items = items.where(is_active: true) unless params[:include_inactive].to_s == "true"
        items = items.where(category: params[:category]) if params[:category].present?

        if params[:grade_id].present?
          # Items with empty grade_ids are available to all grades
          grade_filter = params[:grade_id].to_s
          items = items.any_of({ grade_ids: [] }, { grade_ids: nil }, { grade_ids: grade_filter })
        end

        if params[:only_in_stock].to_s == "true"
          items = items.in_stock
        end

        if params[:q].present?
          regex = /#{Regexp.escape(params[:q].to_s.strip)}/i
          items = items.any_of(
            { name: regex },
            { description: regex },
            { subcategory: regex },
            { subject: regex },
            { tags: regex }
          )
        end

        items = items.order_by(position: :asc, created_at: :desc)

        render json: {
          success: true,
          total: items.count,
          data: items.map(&:to_api_hash)
        }, status: :ok
      rescue StandardError => e
        render_json_exception(e)
      end

      # GET /api/v1/catalog_items/:id
      def show
        render json: {
          success: true,
          data: @catalog_item.to_api_hash
        }, status: :ok
      end

      # POST /api/v1/schools/:school_id/catalog_items
      def create
        item = CatalogItem.new(catalog_item_params)
        item.school_id = @school.id.to_s

        if item.save
          render json: {
            success: true,
            message: "Catalog item created successfully",
            data: item.to_api_hash
          }, status: :created
        else
          render json: {
            success: false,
            error: "Validation failed",
            errors: item.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render_json_exception(e)
      end

      # PATCH/PUT /api/v1/catalog_items/:id
      def update
        if @catalog_item.update(catalog_item_params)
          render json: {
            success: true,
            message: "Catalog item updated successfully",
            data: @catalog_item.to_api_hash
          }, status: :ok
        else
          render json: {
            success: false,
            error: "Validation failed",
            errors: @catalog_item.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render_json_exception(e)
      end

      # DELETE /api/v1/catalog_items/:id (soft delete: is_active = false)
      def destroy
        @catalog_item.update(is_active: false)
        render json: {
          success: true,
          message: "Catalog item deactivated successfully",
          data: @catalog_item.to_api_hash
        }, status: :ok
      rescue StandardError => e
        render_json_exception(e)
      end

      private

      def resolve_user
        auth0_id = params[:auth0_id].presence || request.headers["X-Auth0-Id"].presence
        if auth0_id.blank? && request.headers["Authorization"].present?
          header = request.headers["Authorization"].to_s
          token = header.split.last if header.split.first&.downcase == "bearer"
          if token.present?
            res = Auth0Client.validate_token(token)
            if res.error.nil? && res.decoded_token.present?
              auth0_id = res.decoded_token[:sub] || res.decoded_token["sub"]
            end
          end
        end

        @current_user = User.find_by(auth0_id: auth0_id) if auth0_id.present?
      end

      def set_school
        school_id_param = params[:school_id]
        if school_id_param.blank?
          return render json: { success: false, error: "School ID is required" }, status: :bad_request
        end

        @school = School.find(school_id_param)
      rescue BSON::Error::InvalidObjectId, Mongoid::Errors::DocumentNotFound
        render json: { success: false, error: "School not found" }, status: :not_found
      end

      def set_catalog_item
        @catalog_item = CatalogItem.find(params[:id])
      rescue BSON::Error::InvalidObjectId, Mongoid::Errors::DocumentNotFound
        render json: { success: false, error: "Catalog item not found" }, status: :not_found
      end

      def require_school_admin
        school_id_to_check = @school&.id || @catalog_item&.school_id
        if @current_user.blank?
          return render json: {
            success: false,
            error: "Unauthorized",
            message: "User authentication required"
          }, status: :unauthorized
        end

        unless is_school_admin?(@current_user, school_id_to_check)
          render json: {
            success: false,
            error: "Forbidden",
            message: "Admin access for this school is required"
          }, status: :forbidden
        end
      end

      def is_school_admin?(user, school_id)
        return false if user.blank? || school_id.blank?

        bson_school_id = school_id.is_a?(BSON::ObjectId) ? school_id : BSON::ObjectId.from_string(school_id.to_s)
        UserSchoolRole.where(
          user_id: user.id,
          school_id: bson_school_id,
          role: "Admin"
        ).exists?
      rescue BSON::Error::InvalidObjectId
        false
      end

      def catalog_item_params
        permitted = params.require(:catalog_item).permit(
          :name, :description, :category, :subcategory,
          :price_cents, :currency, :image_url, :is_active,
          :stock_quantity, :subject, :academic_year, :position,
          :file_url,
          grade_ids: [],
          tags: [],
          print_options: %i[color_allowed double_sided_allowed max_copies],
          variants: %i[id label price_cents stock_quantity _destroy]
        )

        permitted_hash = permitted.to_h
        if params[:catalog_item][:variants].is_a?(Array)
          permitted_hash[:variants_attributes] = params[:catalog_item][:variants]
        end
        permitted_hash
      end

      def render_json_exception(exception)
        render json: {
          success: false,
          error: exception.message
        }, status: :internal_server_error
      end
    end
  end
end
