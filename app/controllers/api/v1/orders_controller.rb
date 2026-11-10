# frozen_string_literal: true

module Api
  module V1
    class OrdersController < Api::V1::BaseController
      skip_before_action :authorize, raise: false
      before_action :resolve_user
      before_action :set_school, only: %i[index], if: -> { params[:school_id].present? }
      before_action :set_order, only: %i[show cancel status]

      # GET /api/v1/orders
      # GET /api/v1/schools/:school_id/orders
      def index
        if params[:school_id].present?
          # School admin endpoint
          return render_unauthorized unless @current_user
          return render_forbidden unless is_school_admin?(@current_user, @school.id)

          orders = Order.by_school(@school.id.to_s)
          orders = orders.by_status(params[:status]) if params[:status].present?
          orders = orders.where(learner_id: params[:learner_id]) if params[:learner_id].present?

          if params[:start_date].present?
            begin
              start_time = Time.zone.parse(params[:start_date]).beginning_of_day
              orders = orders.where(:created_at.gte => start_time)
            rescue StandardError
              nil
            end
          end

          if params[:end_date].present?
            begin
              end_time = Time.zone.parse(params[:end_date]).end_of_day
              orders = orders.where(:created_at.lte => end_time)
            rescue StandardError
              nil
            end
          end
        else
          # Parent orders list
          return render_unauthorized unless @current_user

          orders = Order.by_user(@current_user.id)
          orders = orders.by_school(params[:school_id]) if params[:school_id].present?
          orders = orders.by_status(params[:status]) if params[:status].present?
        end

        orders = orders.recent

        render json: {
          success: true,
          total: orders.count,
          data: orders.map(&:to_api_hash)
        }, status: :ok
      rescue StandardError => e
        render_json_exception(e)
      end

      # GET /api/v1/orders/:id
      def show
        return render_unauthorized unless @current_user

        # Access check: user owns order or user is Admin of the school
        is_owner = @order.user_id.to_s == @current_user.id.to_s
        is_admin = is_school_admin?(@current_user, @order.school_id)

        unless is_owner || is_admin
          return render json: {
            success: false,
            error: "Forbidden",
            message: "You do not have permission to view this order"
          }, status: :forbidden
        end

        render json: {
          success: true,
          data: @order.to_api_hash
        }, status: :ok
      end

      # POST /api/v1/orders
      def create
        return render_unauthorized unless @current_user

        school_id_param = params[:school_id] || params.dig(:order, :school_id)
        if school_id_param.blank?
          return render json: { success: false, error: "Validation failed", message: "school_id is required" }, status: :unprocessable_entity
        end

        school = find_school_safe(school_id_param)
        unless school
          return render json: { success: false, error: "School not found" }, status: :not_found
        end

        learner_id_param = params[:learner_id] || params.dig(:order, :learner_id)
        learner = nil
        if learner_id_param.present?
          learner = find_learner_safe(learner_id_param)
          unless learner
            return render json: { success: false, error: "Learner not found" }, status: :not_found
          end

          # Verify learner belongs to school
          unless learner_belongs_to_school?(learner, school.id)
            return render json: {
              success: false,
              error: "Validation failed",
              message: "Learner does not belong to the specified school"
            }, status: :unprocessable_entity
          end

          # Verify learner belongs to parent
          unless parent_owns_learner?(@current_user, learner)
            return render json: {
              success: false,
              error: "Forbidden",
              message: "Learner does not belong to this parent"
            }, status: :forbidden
          end
        end

        items_params = params[:items] || params.dig(:order, :items)
        if items_params.blank? || !items_params.is_a?(Array) || items_params.empty?
          return render json: {
            success: false,
            error: "Validation failed",
            message: "Order must contain at least one item"
          }, status: :unprocessable_entity
        end

        # Validate items and decrement stock atomically
        decremented_items = []
        built_order_items = []

        begin
          items_params.each do |item_input|
            cat_item_id = item_input[:catalog_item_id] || item_input["catalog_item_id"]
            qty = (item_input[:quantity] || item_input["quantity"] || 1).to_i
            variant_label = item_input[:variant_label] || item_input["variant_label"]
            options = (item_input[:options] || item_input["options"] || {}).to_unsafe_h rescue (item_input[:options] || {})

            if qty <= 0
              raise ArgumentError, "Item quantity must be greater than zero"
            end

            catalog_item = CatalogItem.find(cat_item_id)

            # Check school isolation
            if catalog_item.school_id.to_s != school.id.to_s
              raise ArgumentError, "Catalog item '#{catalog_item.name}' does not belong to this school"
            end

            # Check active
            unless catalog_item.is_active
              raise ArgumentError, "Catalog item '#{catalog_item.name}' is inactive"
            end

            # Check grade availability
            if learner&.grade_id.present? && !catalog_item.available_for_grade?(learner.grade_id)
              raise ArgumentError, "Catalog item '#{catalog_item.name}' is not available for the learner's grade"
            end

            # Atomic decrement
            success = CatalogItem.atomic_decrement_stock!(catalog_item.id, variant_label: variant_label, quantity: qty)
            unless success
              raise ArgumentError, "Insufficient stock for item '#{catalog_item.name}'#{variant_label.present? ? " (#{variant_label})" : ''}"
            end

            decremented_items << {
              item_id: catalog_item.id,
              variant_label: variant_label,
              quantity: qty
            }

            # Server-side recomputed price snapshot
            unit_price = catalog_item.effective_price_cents(variant_label)

            order_item = OrderItem.new(
              catalog_item_id: catalog_item.id.to_s,
              name_snapshot: catalog_item.name,
              category_snapshot: catalog_item.category,
              unit_price_cents: unit_price,
              quantity: qty,
              variant_label: variant_label,
              options: options
            )
            built_order_items << order_item
          end

          # Create Order
          notes_param = params[:notes] || params.dig(:order, :notes)
          order = Order.new(
            school_id: school.id.to_s,
            user_id: @current_user.id.to_s,
            learner_id: learner&.id&.to_s,
            notes: notes_param,
            status: "placed",
            currency: school.try(:currency) || "ZAR",
            payment_status: "unpaid",
            fulfilment_method: "collect"
          )

          built_order_items.each { |oi| order.items << oi }
          order.calculate_subtotal_cents!

          if order.save
            render json: {
              success: true,
              message: "Order placed successfully",
              data: order.to_api_hash
            }, status: :created
          else
            # Rollback stock
            rollback_stock(decremented_items)
            render json: {
              success: false,
              error: "Validation failed",
              errors: order.errors.full_messages
            }, status: :unprocessable_entity
          end
        rescue ArgumentError => e
          rollback_stock(decremented_items)
          render json: {
            success: false,
            error: "Validation failed",
            message: e.message
          }, status: :unprocessable_entity
        rescue BSON::Error::InvalidObjectId, Mongoid::Errors::DocumentNotFound => e
          rollback_stock(decremented_items)
          render json: {
            success: false,
            error: "Not found",
            message: "Catalog item not found"
          }, status: :not_found
        rescue StandardError => e
          rollback_stock(decremented_items)
          render_json_exception(e)
        end
      end

      # POST /api/v1/orders/:id/cancel
      def cancel
        return render_unauthorized unless @current_user

        # Access check: Parent owner or School Admin
        is_owner = @order.user_id.to_s == @current_user.id.to_s
        is_admin = is_school_admin?(@current_user, @order.school_id)

        unless is_owner || is_admin
          return render json: {
            success: false,
            error: "Forbidden",
            message: "You do not have permission to cancel this order"
          }, status: :forbidden
        end

        # If parent, must be in placed status
        if is_owner && !is_admin && @order.status != "placed"
          return render json: {
            success: false,
            error: "Validation failed",
            message: "Parents may only cancel orders in placed status"
          }, status: :unprocessable_entity
        end

        success = @order.transition_to!("cancelled", by_user_id: @current_user.id)
        if success
          render json: {
            success: true,
            message: "Order cancelled successfully",
            data: @order.to_api_hash
          }, status: :ok
        else
          render json: {
            success: false,
            error: "Validation failed",
            errors: @order.errors.full_messages
          }, status: :unprocessable_entity
        end
      rescue StandardError => e
        render_json_exception(e)
      end

      # PATCH /api/v1/orders/:id/status
      def status
        return render_unauthorized unless @current_user

        unless is_school_admin?(@current_user, @order.school_id)
          return render json: {
            success: false,
            error: "Forbidden",
            message: "Admin access for this school is required to change order status"
          }, status: :forbidden
        end

        new_status = params[:status] || params.dig(:order, :status)
        if new_status.blank?
          return render json: {
            success: false,
            error: "Validation failed",
            message: "status is required"
          }, status: :unprocessable_entity
        end

        unless Order::STATUSES.include?(new_status)
          return render json: {
            success: false,
            error: "Validation failed",
            message: "Invalid status '#{new_status}'"
          }, status: :unprocessable_entity
        end

        success = @order.transition_to!(new_status, by_user_id: @current_user.id)
        if success
          render json: {
            success: true,
            message: "Order status updated to #{new_status}",
            data: @order.to_api_hash
          }, status: :ok
        else
          render json: {
            success: false,
            error: "Validation failed",
            errors: @order.errors.full_messages
          }, status: :unprocessable_entity
        end
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
        return if school_id_param.blank?

        @school = find_school_safe(school_id_param)
        unless @school
          render json: { success: false, error: "School not found" }, status: :not_found
        end
      end

      def set_order
        @order = Order.find(params[:id])
      rescue BSON::Error::InvalidObjectId, Mongoid::Errors::DocumentNotFound
        render json: { success: false, error: "Order not found" }, status: :not_found
      end

      def find_school_safe(school_id_param)
        return nil if school_id_param.blank?

        if school_id_param.to_s.match?(/\A[0-9a-f]{24}\z/i)
          School.find_by(_id: BSON::ObjectId.from_string(school_id_param.to_s))
        else
          School.find_by(schoolName: school_id_param.to_s)
        end
      rescue BSON::Error::InvalidObjectId
        nil
      end

      def find_learner_safe(learner_id_param)
        return nil if learner_id_param.blank?

        if learner_id_param.to_s.match?(/\A[0-9a-f]{24}\z/i)
          raw = Learner.collection.find(_id: BSON::ObjectId.from_string(learner_id_param.to_s)).first
          raw ? Learner.instantiate(raw) : nil
        else
          raw = Learner.collection.find(accession_number: learner_id_param.to_s).first ||
                Learner.collection.find(accessionNumber: learner_id_param.to_s).first
          raw ? Learner.instantiate(raw) : nil
        end
      rescue BSON::Error::InvalidObjectId
        nil
      end

      def learner_belongs_to_school?(learner, school_id)
        s_id = school_id.to_s
        l_school_id = learner.try(:school_id).to_s
        l_school_id == s_id
      end

      def parent_owns_learner?(user, learner)
        return false if user.blank? || learner.blank?

        parent_ids = learner.try(:parent_ids) || []
        user_id_str = user.id.to_s
        user_auth0 = user.auth0_id.to_s

        parent_ids.any? do |pid|
          pid.to_s == user_id_str || (user_auth0.present? && pid.to_s == user_auth0)
        end || learner.try(:userAuth0Id).to_s == user_auth0 || learner.try(:auth0Id).to_s == user_auth0
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

      def rollback_stock(decremented_items)
        decremented_items.each do |item|
          CatalogItem.atomic_increment_stock!(
            item[:item_id],
            variant_label: item[:variant_label],
            quantity: item[:quantity]
          )
        end
      end

      def render_unauthorized
        render json: {
          success: false,
          error: "Unauthorized",
          message: "User authentication required"
        }, status: :unauthorized
      end

      def render_forbidden
        render json: {
          success: false,
          error: "Forbidden",
          message: "Admin access for this school is required"
        }, status: :forbidden
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
